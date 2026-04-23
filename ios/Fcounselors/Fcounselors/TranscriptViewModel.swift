import Foundation
import SwiftUI

@MainActor
final class TranscriptViewModel: ObservableObject {
    @Published var result: TranscriptResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func upload(fileData: Data, mimeType: String, fileName: String) async {
        isLoading = true
        errorMessage = nil
        result = nil
        do {
            result = try await APIService.uploadTranscript(fileData: fileData, mimeType: mimeType, fileName: fileName)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func reset() {
        result = nil
        errorMessage = nil
    }
}
