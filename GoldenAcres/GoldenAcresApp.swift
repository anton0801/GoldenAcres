//
//  GoldenAcresApp.swift
//  GoldenAcres
//
//  Created by Anton Danilov on 12/8/26.
//

import SwiftUI
import SwiftData

@main
struct GoldenAcresApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authStore = AuthStore()

    /// The store starts empty on purpose. No demo farm, no sample field —
    /// the first record in the app is one the user actually created.
    let container: ModelContainer = {
        let schema = Schema([
            Farm.self,
            FarmField.self,
            CropSeason.self,
            TeamMember.self,
            FieldObservation.self,
            SoilTest.self,
            IrrigationPlan.self,
            IrrigationRun.self,
            InputApplication.self,
            FarmTask.self,
            InventoryLot.self,
            StockMovement.self,
            HarvestBatch.self,
            HarvestLoad.self,
            AuditEvent.self,
            SeasonReviewRecord.self,
            DataConnection.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A store that cannot be opened is surfaced rather than hidden
            // behind an in-memory fallback that would silently lose data.
            fatalError("Could not open the local data store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(authStore)
                .environmentObject(DraftStore.shared)
                .preferredColorScheme(.dark)
                .tint(Palette.gold)
        }
        .modelContainer(container)
    }
}
