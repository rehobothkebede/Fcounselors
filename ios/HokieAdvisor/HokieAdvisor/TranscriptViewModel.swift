import Foundation
import SwiftUI
import Combine

@MainActor
final class TranscriptViewModel: ObservableObject {
    @Published var result: TranscriptResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var errorTitle = "Upload failed"

    func upload(fileData: Data, mimeType: String, fileName: String) async {
        isLoading = true
        errorMessage = nil
        errorTitle = "Upload failed"
        result = nil
        do {
            result = try await APIService.uploadTranscript(fileData: fileData, mimeType: mimeType, fileName: fileName)
        } catch {
            if let apiError = error as? APIError {
                errorTitle = apiError.userTitle
            }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func reset() {
        result = nil
        errorMessage = nil
        errorTitle = "Upload failed"
    }
}
