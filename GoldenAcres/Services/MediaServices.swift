//
//  MediaServices.swift
//  GoldenAcres
//
//  Photo storage, on-device image classification and lab-report OCR.
//
//  Both analysers run locally through Vision. They only ever produce
//  *suggestions* with a real confidence figure attached. Low confidence is
//  reported as "unable to identify reliably" rather than guessed, and no
//  result replaces the original file.
//

import Foundation
import UIKit
import Vision
import PDFKit

// MARK: - Photo storage

enum PhotoStore {
    static let directoryName = "ObservationPhotos"

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Saves the original image untouched and returns its filename.
    static func save(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return name
        } catch {
            return nil
        }
    }

    static func saveFile(data: Data, extension ext: String) -> String? {
        let name = "\(UUID().uuidString).\(ext)"
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return name
        } catch {
            return nil
        }
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    static func load(_ filename: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: filename).path)
    }

    static func exists(_ filename: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: filename).path)
    }

    static func delete(_ filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
    }
}

// MARK: - Image suggestion

enum ImageSuggestionService {
    static let sourceName = "Apple Vision (on-device)"

    /// Confidence below this is reported as unusable rather than shown as a
    /// category the user might act on.
    static let reliabilityThreshold: Double = 0.25

    /// Returns a *suggested* category. It never names a disease, never
    /// prescribes treatment, and never overwrites the stored photo.
    static func classify(image: UIImage) async -> ImageSuggestion {
        let provenance = Provenance(source: sourceName,
                                    sourceDetail: "VNClassifyImageRequest",
                                    retrievedAt: Date())

        guard let cgImage = image.cgImage else {
            return ImageSuggestion(suggestedCategory: nil, confidence: nil,
                                   provenance: provenance, isReliable: false,
                                   message: "The photo could not be read for analysis.")
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let observations = (request.results ?? [])
                        .filter { $0.confidence > 0 }
                        .sorted { $0.confidence > $1.confidence }

                    guard let best = observations.first else {
                        continuation.resume(returning: ImageSuggestion(
                            suggestedCategory: nil, confidence: nil,
                            provenance: provenance, isReliable: false,
                            message: "Unable to identify reliably. Choose a category yourself."))
                        return
                    }

                    let confidence = Double(best.confidence)
                    let reliable = confidence >= reliabilityThreshold
                    let label = best.identifier.replacingOccurrences(of: "_", with: " ")

                    continuation.resume(returning: ImageSuggestion(
                        suggestedCategory: reliable ? label : nil,
                        confidence: confidence,
                        provenance: provenance,
                        isReliable: reliable,
                        message: reliable
                            ? "This is a generic image label, not an agronomic diagnosis. Confirm or replace it."
                            : "Unable to identify reliably (best guess “\(label)” at \(Int(confidence * 100))%). Choose a category yourself."
                    ))
                } catch {
                    continuation.resume(returning: ImageSuggestion(
                        suggestedCategory: nil, confidence: nil,
                        provenance: provenance, isReliable: false,
                        message: "Image analysis failed: \(error.localizedDescription)"))
                }
            }
        }
    }
}

// MARK: - Soil report parsing

struct SoilParseResult {
    var suggestions: [ParsedFieldSuggestion]
    var rawText: String
    var provenance: Provenance
    var failureReason: String?

    var isUsable: Bool { !suggestions.isEmpty }
}

enum SoilReportParser {
    static let sourceName = "On-device text recognition"

    /// Extracts candidate values from a PDF or photo. Everything returned is a
    /// draft suggestion with its own confidence and page location — nothing is
    /// written to the record until the user confirms it.
    static func parse(fileURL: URL) async -> SoilParseResult {
        let provenance = Provenance(source: sourceName,
                                    sourceDetail: fileURL.lastPathComponent,
                                    retrievedAt: Date())

        var text = ""
        if fileURL.pathExtension.lowercased() == "pdf" {
            text = extractPDFText(url: fileURL)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let image = renderFirstPage(url: fileURL) {
                text = await recognizeText(in: image)
            }
        } else if let image = UIImage(contentsOfFile: fileURL.path) {
            text = await recognizeText(in: image)
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SoilParseResult(
                suggestions: [], rawText: "", provenance: provenance,
                failureReason: "No readable text was found in this file. The file has been saved — enter the values manually."
            )
        }

        let suggestions = extractValues(from: text)
        return SoilParseResult(
            suggestions: suggestions,
            rawText: text,
            provenance: provenance,
            failureReason: suggestions.isEmpty
                ? "This layout is not recognised. The file and your notes are saved — enter the values manually."
                : nil
        )
    }

    static func parse(image: UIImage) async -> SoilParseResult {
        let provenance = Provenance(source: sourceName,
                                    sourceDetail: "Photo of report",
                                    retrievedAt: Date())
        let text = await recognizeText(in: image)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SoilParseResult(suggestions: [], rawText: "", provenance: provenance,
                                   failureReason: "No readable text was found in this photo. Enter the values manually.")
        }
        let suggestions = extractValues(from: text)
        return SoilParseResult(
            suggestions: suggestions, rawText: text, provenance: provenance,
            failureReason: suggestions.isEmpty
                ? "This layout is not recognised. Enter the values manually."
                : nil
        )
    }

    // MARK: PDF

    private static func extractPDFText(url: URL) -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        var out = ""
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let content = page.string {
                out += "\n[page \(index + 1)]\n" + content
            }
        }
        return out
    }

    private static func renderFirstPage(url: URL) -> UIImage? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    // MARK: OCR

    private static func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let lines = (request.results ?? []).compactMap {
                        $0.topCandidates(1).first?.string
                    }
                    continuation.resume(returning: lines.joined(separator: "\n"))
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    // MARK: Value extraction

    private struct Pattern {
        var key: String
        var regex: String
        var defaultUnit: String?
    }

    private static let patterns: [Pattern] = [
        Pattern(key: "pH", regex: #"\bp\s?H\b[^0-9\-]{0,12}(\d{1,2}(?:[.,]\d{1,2})?)"#, defaultUnit: nil),
        Pattern(key: "Organic matter", regex: #"(?:organic\s*matter|\bO\.?M\.?\b)[^0-9\-]{0,12}(\d{1,2}(?:[.,]\d{1,2})?)\s*(%)?"#, defaultUnit: "%"),
        Pattern(key: "Nitrogen", regex: #"(?:nitrogen|\bN\b)[^0-9\-]{0,12}(\d{1,4}(?:[.,]\d{1,2})?)\s*(ppm|mg\/kg|%)?"#, defaultUnit: nil),
        Pattern(key: "Phosphorus", regex: #"(?:phosphorus|\bP2O5\b|\bP\b)[^0-9\-]{0,12}(\d{1,4}(?:[.,]\d{1,2})?)\s*(ppm|mg\/kg|%)?"#, defaultUnit: nil),
        Pattern(key: "Potassium", regex: #"(?:potassium|\bK2O\b|\bK\b)[^0-9\-]{0,12}(\d{1,4}(?:[.,]\d{1,2})?)\s*(ppm|mg\/kg|%)?"#, defaultUnit: nil),
        Pattern(key: "Salinity", regex: #"(?:salinity|conductivity|\bEC\b)[^0-9\-]{0,12}(\d{1,3}(?:[.,]\d{1,3})?)\s*(dS\/m|mS\/cm)?"#, defaultUnit: "dS/m")
    ]

    static func extractValues(from text: String) -> [ParsedFieldSuggestion] {
        let lines = text.components(separatedBy: .newlines)
        var results: [ParsedFieldSuggestion] = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.regex,
                                                       options: [.caseInsensitive]) else { continue }
            for (index, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                guard let match = regex.firstMatch(in: line, options: [], range: range) else { continue }

                guard match.numberOfRanges > 1,
                      let valueRange = Range(match.range(at: 1), in: line) else { continue }
                let rawValue = String(line[valueRange]).replacingOccurrences(of: ",", with: ".")
                guard let numeric = Double(rawValue) else { continue }

                var unitText: String? = pattern.defaultUnit
                if match.numberOfRanges > 2,
                   let unitRange = Range(match.range(at: 2), in: line) {
                    let found = String(line[unitRange]).trimmingCharacters(in: .whitespaces)
                    if !found.isEmpty { unitText = found }
                }

                // Confidence reflects how much context supported the match: a
                // value with an explicit unit on a short, label-like line is
                // more trustworthy than a bare number in prose.
                var confidence = 0.5
                if unitText != nil { confidence += 0.25 }
                if line.count < 40 { confidence += 0.15 }
                if line.lowercased().contains(pattern.key.lowercased()) { confidence += 0.1 }
                confidence = min(confidence, 0.95)

                // Keep only the best match per key.
                if let existing = results.firstIndex(where: { $0.fieldKey == pattern.key }) {
                    if results[existing].confidence >= confidence { continue }
                    results.remove(at: existing)
                }

                results.append(ParsedFieldSuggestion(
                    fieldKey: pattern.key,
                    rawText: line.trimmingCharacters(in: .whitespaces),
                    numericValue: numeric,
                    unitText: unitText,
                    confidence: confidence,
                    sourceLocation: "line \(index + 1)"
                ))
            }
        }
        return results.sorted { $0.fieldKey < $1.fieldKey }
    }
}
