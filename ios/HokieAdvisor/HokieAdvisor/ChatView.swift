import SwiftUI
import UIKit
import Combine
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var chatHistory: ChatHistoryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var vm = ChatViewModel()
    private let topID = "chatTop"
    private let bottomID = "chatBottom"
    private let emptyStateBottomID = "chatEmptyStateBottom"
    private let keyboardComposerGap: CGFloat = 24
    private let keyboardMessageBottomPadding: CGFloat = 152
    @State private var showHistory = false
    @State private var showAttachmentMenu = false
    @State private var showCameraPicker = false
    @State private var showFileImporter = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedAttachment: ChatAttachment?
    @State private var isKeyboardVisible = false
    @State private var scrollOffset: CGFloat = 0
    @FocusState private var isInputFocused: Bool

    private var hasDraft: Bool {
        !vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasSendableDraft: Bool {
        hasDraft || selectedAttachment != nil
    }

    private var draftMessageText: String {
        let text = vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let selectedAttachment else { return text }
        return text.isEmpty
            ? selectedAttachment.promptContext
            : "\(selectedAttachment.promptContext)\n\n\(text)"
    }

    private var canSubmitDraft: Bool {
        vm.canSend(text: draftMessageText)
    }

    private var keyboardAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.38, dampingFraction: 0.90, blendDuration: 0.08)
    }

    private var controlAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.30, dampingFraction: 0.86, blendDuration: 0.04)
    }

    private var composerBottomPadding: CGFloat {
        isKeyboardVisible ? keyboardComposerGap : HokieChrome.chatComposerRestingBottom
    }

    private var messageBottomPadding: CGFloat {
        isKeyboardVisible ? keyboardMessageBottomPadding : HokieChrome.chatMessageRestingBottom
    }

    private var shouldKeepInputVisible: Bool {
        isKeyboardVisible && isInputFocused
    }

    private var compactTitleProgress: CGFloat {
        guard !vm.messages.isEmpty else { return 0 }
        return min(max((scrollOffset - 82) / 34, 0), 1)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                messageList
                inputBar
            }
            .hokieScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .transparentNavigationChrome()
            .overlay(alignment: .top) { compactTitleOverlay }
        }
        .swipeDownToDismissKeyboard()
        .onKeyboardVisibilityChange { visible in
            withAnimation(keyboardAnimation) {
                isKeyboardVisible = visible
            }
        }
        .animation(keyboardAnimation, value: isKeyboardVisible)
        .onAppear {
            vm.configure(store: chatHistory)
            if vm.major.isEmpty && !appState.major.isEmpty { vm.major = appState.major }
            vm.transcriptCourses = appState.transcriptCourses
            vm.inProgressSummary = appState.inProgressSummary
            vm.transcriptNotes = appState.transcriptNotes
        }
        .onDisappear { vm.autoSave() }
        .onChange(of: appState.major) { _, major in
            if !major.isEmpty { vm.major = major }
        }
        .onChange(of: appState.transcriptCourses) { _, courses in
            vm.transcriptCourses = courses
            vm.inProgressSummary = appState.inProgressSummary
            vm.transcriptNotes = appState.transcriptNotes
        }
        .onChange(of: appState.transcriptNotes) { _, notes in
            vm.transcriptNotes = notes
        }
        .sheet(isPresented: $showHistory) {
            ChatHistorySheet(vm: vm)
                .environmentObject(chatHistory)
        }
        .sheet(isPresented: $showCameraPicker) {
            CameraCaptureView { image in
                selectedAttachment = ChatAttachment(
                    kind: .camera,
                    name: "Camera photo",
                    image: image,
                    data: image.jpegData(compressionQuality: 0.86)
                )
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false,
            onCompletion: handlePickedFile
        )
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await handlePickedPhoto(item) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HokiePageHeader(
            title: "Advisor",
            eyebrow: "Ask / plan / prove",
            subtitle: "Visual math, CS planning, and chat memory for your next move.",
            symbol: "bubble.left.and.bubble.right.fill",
            accent: .vtBurgundy,
            stat: vm.messages.isEmpty ? nil : advisorHeaderStat
        ) {
            HStack(spacing: 8) {
                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(Color.vtBurgundy)
                        .frame(width: 38, height: 38)
                        .glassCapsule(strokeOpacity: 0.08)
                }
                .accessibilityLabel("Chat history")

                if !vm.messages.isEmpty {
                    Button { vm.clearConversation() } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(Color.vtBurgundy)
                            .frame(width: 38, height: 38)
                            .glassCapsule(strokeOpacity: 0.08)
                    }
                    .accessibilityLabel("New chat")
                }
            }
        }
    }

    private var advisorHeaderStat: HokieHeaderStat {
        if !vm.messages.isEmpty {
            return HokieHeaderStat(value: "\(vm.messages.count)", label: "messages", icon: "text.bubble.fill")
        }
        if chatHistory.sessions.isEmpty {
            return HokieHeaderStat(value: "Ready", label: "new chat", icon: "sparkles")
        }
        return HokieHeaderStat(value: "\(chatHistory.sessions.count)", label: "saved chats", icon: "clock.arrow.circlepath")
    }

    private var compactTitleOverlay: some View {
        HokieCompactPill(
            title: "Advisor",
            symbol: "bubble.left.and.bubble.right.fill",
            accent: .vtBurgundy,
            progress: compactTitleProgress
        )
            .padding(.top, 8)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 10) {
                        Color.clear
                            .frame(height: 1)
                            .id(topID)
                        header
                        if vm.messages.isEmpty {
                            emptyState
                            Color.clear
                                .frame(height: messageBottomPadding)
                                .id(emptyStateBottomID)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(vm.messages) { MessageBubble(message: $0) }
                                if vm.isLoading { TypingIndicator() }
                                if let error = vm.errorMessage { ErrorBanner(message: error) }
                                Color.clear
                                    .frame(height: messageBottomPadding)
                                    .id(bottomID)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, offset in
                    guard abs(offset - scrollOffset) > 0.5 else { return }
                    scrollOffset = offset
                }

                if !vm.messages.isEmpty {
                    Button {
                        withAnimation(keyboardAnimation) {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 46, height: 46)
                            .glassCapsule(strokeOpacity: 0.10)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, composerBottomPadding + 62)
                    .accessibilityLabel("Jump to latest message")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                guard vm.messages.isEmpty else { return }
                if shouldKeepInputVisible {
                    scrollKeyboardTargetIntoView(proxy)
                } else {
                    resetEmptyChatToTop(proxy)
                }
            }
            .onChange(of: isKeyboardVisible) { _, visible in
                guard visible, isInputFocused else { return }
                scrollKeyboardTargetIntoView(proxy)
            }
            .onChange(of: isInputFocused) { _, focused in
                guard focused, isKeyboardVisible else { return }
                scrollKeyboardTargetIntoView(proxy)
            }
            .onChange(of: vm.messages.count) { _, count in
                if count == 0 {
                    if shouldKeepInputVisible {
                        scrollKeyboardTargetIntoView(proxy)
                    } else {
                        withAnimation(keyboardAnimation) {
                            proxy.scrollTo(topID, anchor: .top)
                        }
                    }
                } else {
                    withAnimation(keyboardAnimation) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: vm.isLoading) { _, _ in
                guard !vm.messages.isEmpty else { return }
                withAnimation(keyboardAnimation) { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
            .onChange(of: vm.messages.last?.content) { _, _ in
                guard !vm.messages.isEmpty else { return }
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            MiniGraphPreview()
                .frame(height: 124)

            VStack(spacing: 6) {
                Text("Math + CS tutor")
                    .font(.title3.bold()).fontDesign(.rounded)
                Text("Graph theory, algorithms, proofs, linear algebra, calculus, and VT planning.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                TopicChip(icon: "point.3.connected.trianglepath.dotted", label: "Graph theory")
                TopicChip(icon: "function", label: "Calculus")
                TopicChip(icon: "square.grid.3x3.fill", label: "Linear algebra")
                TopicChip(icon: "chevron.left.forwardslash.chevron.right", label: "Algorithms")
            }

            VStack(spacing: 7) {
                if appState.needsTutoringSupport {
                    SuggestionChip(
                        text: "I'm struggling with \(appState.strugglingCourses.first ?? "my classes"). What should I do?",
                        vm: vm
                    )
                }
                ForEach(suggestionChips, id: \.self) { text in
                    SuggestionChip(text: text, vm: vm)
                }
            }
        }
        .padding(.top, 20).padding(.horizontal, 16)
    }

    private func resetEmptyChatToTop(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(topID, anchor: .top)
        }
    }

    private func scrollKeyboardTargetIntoView(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(keyboardAnimation) {
                if vm.messages.isEmpty {
                    proxy.scrollTo(emptyStateBottomID, anchor: .bottom)
                } else {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
        }
    }

    private var suggestionChips: [String] {
        let major = vm.major.isEmpty ? (appState.major.isEmpty ? "my major" : appState.major) : vm.major
        return [
            "Show me BFS on a graph with a visual",
            "Explain paths vs circuits in graph theory",
            "Walk me through an eigenvalue example",
            "Help me prove a recurrence by induction",
            "What \(major) courses should I take next semester?",
        ]
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let attachment = selectedAttachment {
                ChatAttachmentChip(attachment: attachment) {
                    withAnimation(controlAnimation) {
                        selectedAttachment = nil
                    }
                }
                .padding(.leading, 66)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.96, anchor: .bottomLeading).combined(with: .opacity)
                    )
                )
            }

            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 10) {
                    ChatComposerCircleButton(systemName: "plus", isActive: showAttachmentMenu) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(controlAnimation) {
                            showAttachmentMenu.toggle()
                        }
                    }

                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Ask a question...", text: $vm.inputText, axis: .vertical)
                            .focused($isInputFocused)
                            .lineLimit(1...5)
                            .submitLabel(.return)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled(false)
                            .tint(Color.vtBurgundy)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .padding(.leading, 18)
                            .padding(.vertical, 13)

                        Group {
                            if hasSendableDraft {
                                Button {
                                    sendDraft()
                                } label: {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(canSubmitDraft ? Color.white : Color.secondary)
                                        .frame(width: 38, height: 38)
                                        .background(canSubmitDraft ? Color.vtBurgundy : Color.primary.opacity(0.08), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!canSubmitDraft)
                                .id("send")
                                .transition(.scale(scale: 0.82).combined(with: .opacity))
                                .accessibilityLabel("Send message")
                            } else {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Image(systemName: "mic")
                                        .font(.system(size: 21, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 38, height: 38)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Voice transcription placeholder")
                                .id("mic")
                                .transition(.scale(scale: 0.88).combined(with: .opacity))
                            }
                        }
                        .padding(.trailing, 8)
                        .padding(.bottom, 5)
                    }
                    .glassSurface(cornerRadius: 28, strokeOpacity: 0.08)
                    .animation(controlAnimation, value: hasSendableDraft)
                }

                if showAttachmentMenu {
                    ChatAttachmentMenu(
                        cameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera),
                        onCamera: {
                            showAttachmentMenu = false
                            showCameraPicker = true
                        },
                        onFiles: {
                            showAttachmentMenu = false
                            showFileImporter = true
                        },
                        selectedPhotoItem: $selectedPhotoItem
                    )
                    .offset(x: 0, y: -64)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92, anchor: .bottomLeading)
                                .combined(with: .opacity)
                                .combined(with: .move(edge: .bottom)),
                            removal: .scale(scale: 0.96, anchor: .bottomLeading)
                                .combined(with: .opacity)
                        )
                    )
                    .zIndex(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, composerBottomPadding)
        .offset(y: isKeyboardVisible ? -3 : 0)
        .shadow(color: Color.black.opacity(isKeyboardVisible ? 0.08 : 0.04), radius: isKeyboardVisible ? 18 : 10, x: 0, y: 8)
        .background(.clear)
        .animation(keyboardAnimation, value: isKeyboardVisible)
        .animation(controlAnimation, value: selectedAttachment?.id)
        .animation(controlAnimation, value: showAttachmentMenu)
    }

    private func sendDraft() {
        let textToSend = draftMessageText
        guard vm.canSend(text: textToSend) else { return }
        let attachmentToRestore = selectedAttachment
        let typedTextToRestore = vm.inputText

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIApplication.shared.dismissKeyboard()
        showAttachmentMenu = false
        selectedAttachment = nil

        Task { @MainActor in
            let sent = await vm.sendMessage(textOverride: textToSend)
            if !sent {
                selectedAttachment = attachmentToRestore
                vm.inputText = typedTextToRestore
            }
        }
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let type = item.supportedContentTypes.first ?? .image
            let extensionName = type.preferredFilenameExtension ?? "jpg"
            await MainActor.run {
                selectedAttachment = ChatAttachment(
                    kind: .photo,
                    name: "Photo.\(extensionName)",
                    image: UIImage(data: data),
                    data: data
                )
                selectedPhotoItem = nil
                showAttachmentMenu = false
            }
        } catch {
            await MainActor.run {
                vm.errorMessage = "Could not load the selected photo."
                selectedPhotoItem = nil
                showAttachmentMenu = false
            }
        }
    }

    private func handlePickedFile(_ pickerResult: Result<[URL], Error>) {
        showAttachmentMenu = false
        switch pickerResult {
        case .failure:
            vm.errorMessage = "Could not open the selected file."
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            selectedAttachment = ChatAttachment(
                kind: .file,
                name: url.lastPathComponent,
                image: nil,
                data: try? Data(contentsOf: url)
            )
        }
    }
}

struct ChatComposerCircleButton: View {
    let systemName: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .glassCircle(strokeOpacity: 0.08)
                .rotationEffect(.degrees(isActive ? 45 : 0))
                .animation(.spring(response: 0.30, dampingFraction: 0.86, blendDuration: 0.04), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Close attachment menu" : "Add attachment")
    }
}

struct ChatAttachment: Identifiable {
    enum Kind {
        case camera, photo, file

        var label: String {
            switch self {
            case .camera: return "Camera"
            case .photo:  return "Photo"
            case .file:   return "File"
            }
        }

        var icon: String {
            switch self {
            case .camera: return "camera.fill"
            case .photo:  return "photo"
            case .file:   return "doc.fill"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let name: String
    let image: UIImage?
    let data: Data?

    var promptContext: String {
        let sizeText = data.map { ByteCountFormatter.string(fromByteCount: Int64($0.count), countStyle: .file) }
        let sizeSuffix = sizeText.map { " (\($0))" } ?? ""
        return "Attachment queued in Hokie Advisor: \(kind.label.lowercased()) \"\(name)\"\(sizeSuffix). Direct file analysis is not connected yet, so use any written context below and ask me for a description if you need the file contents."
    }
}

struct ChatAttachmentChip: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let image = attachment.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: attachment.kind.icon)
                    .font(.caption.bold())
                    .foregroundStyle(Color.vtBurgundy)
                    .frame(width: 34, height: 34)
                    .glassCircle(strokeOpacity: 0.08)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.kind.label)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Text(attachment.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassCapsule(strokeOpacity: 0.08)
    }
}

struct ChatAttachmentMenu: View {
    let cameraAvailable: Bool
    let onCamera: () -> Void
    let onFiles: () -> Void
    @Binding var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onCamera) {
                AttachmentMenuRow(icon: "camera", title: "Camera")
            }
            .buttonStyle(.plain)
            .disabled(!cameraAvailable)
            .opacity(cameraAvailable ? 1 : 0.45)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                AttachmentMenuRow(icon: "photo", title: "Photos")
            }
            .buttonStyle(.plain)

            Button(action: onFiles) {
                AttachmentMenuRow(icon: "paperclip", title: "Files")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(width: 250, alignment: .leading)
        .glassSurface(cornerRadius: 30, strokeOpacity: 0.08)
    }
}

struct AttachmentMenuRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 18) {
            HokieIconTile(symbol: icon, color: .vtBurgundy, size: 44)
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == "user" }

    @ViewBuilder
    private var bubbleContent: some View {
        if isUser {
            Text(message.content)
                .font(.subheadline).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.vtBurgundy.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: 22))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                MarkdownBody(text: message.content.isEmpty ? " " : message.content, baseColor: .primary)
                if message.isStreaming {
                    StreamingCursor()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }
            bubbleContent
        }
    }
}

// MARK: - Streaming Cursor

struct StreamingCursor: View {
    @State private var visible = true
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .frame(width: 2, height: 14)
            .foregroundStyle(Color.vtBurgundy)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: visible)
            .onReceive(timer) { _ in visible.toggle() }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase = 0
    let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HokieIconTile(symbol: "brain.head.profile", color: .vtBurgundy, size: 32)

            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle().frame(width: 7, height: 7)
                        .foregroundStyle(Color.secondary.opacity(phase == i ? 1 : 0.3))
                        .animation(.easeInOut(duration: 0.3), value: phase)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .glassSurface(cornerRadius: 22)

            Spacer(minLength: 48)
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14).frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: 18)
    }
}

// MARK: - Suggestion Chip

struct SuggestionChip: View {
    let text: String
    let vm: ChatViewModel

    var body: some View {
        Button {
            vm.inputText = text
            Task { await vm.sendMessage() }
        } label: {
            Text(text).font(.subheadline).foregroundStyle(Color.vtBurgundy)
                .padding(.horizontal, 15).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(cornerRadius: 18, strokeOpacity: 0.07)
        }
    }
}

struct TopicChip: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(Color.vtBurgundy)
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 12, strokeOpacity: 0.06)
    }
}

struct MiniGraphPreview: View {
    private let nodes: [(String, CGPoint)] = [
        ("A", CGPoint(x: 0.18, y: 0.24)),
        ("B", CGPoint(x: 0.50, y: 0.18)),
        ("C", CGPoint(x: 0.30, y: 0.72)),
        ("D", CGPoint(x: 0.72, y: 0.66)),
        ("E", CGPoint(x: 0.84, y: 0.30)),
    ]

    private let edges = [(0, 1), (0, 2), (1, 3), (1, 4), (2, 3), (3, 4)]
    private let path = Set([0, 1, 3])
    private let pathEdges = Set(["0-1", "1-3"])

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.clear)
                    .glassSurface(cornerRadius: 18, strokeOpacity: 0.08)

                ForEach(Array(edges.enumerated()), id: \.offset) { _, edge in
                    let a = scaled(nodes[edge.0].1, in: proxy.size)
                    let b = scaled(nodes[edge.1].1, in: proxy.size)
                    let key = "\(edge.0)-\(edge.1)"
                    Path { path in
                        path.move(to: a)
                        path.addLine(to: b)
                    }
                    .stroke(
                        pathEdges.contains(key) ? Color.vtBurgundy : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: pathEdges.contains(key) ? 4 : 1.5, lineCap: .round)
                    )
                }

                ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
                    let highlighted = path.contains(index)
                    Text(node.0)
                        .font(.caption.bold())
                        .foregroundStyle(highlighted ? .white : .primary)
                        .frame(width: 36, height: 36)
                        .background {
                            Circle()
                                .fill(
                                    highlighted
                                        ? LinearGradient(
                                            colors: [Color.vtBurgundy.opacity(0.92), Color.vtOrange.opacity(0.38)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        : LinearGradient(
                                            colors: [Color.primary.opacity(0.08), Color.white.opacity(0.02)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                )
                        }
                        .overlay(Circle().stroke(Color.secondary.opacity(0.20), lineWidth: 1))
                        .position(scaled(node.1, in: proxy.size))
                }

                VStack {
                    Spacer()
                    HStack {
                        Label("shortest path A → D", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Color.vtBurgundy)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.vtBurgundy.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.vtBurgundy.opacity(0.14), lineWidth: 1))
                        Spacer()
                    }
                    .padding(12)
                }
            }
        }
    }

    private func scaled(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}

// MARK: - Chat History Sheet

struct ChatHistorySheet: View {
    @EnvironmentObject var chatHistory: ChatHistoryStore
    @ObservedObject var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if chatHistory.sessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 46))
                            .foregroundStyle(Color.vtBurgundy.opacity(0.4))
                        Text("No saved chats yet")
                            .font(.title3.bold()).fontDesign(.rounded)
                            .foregroundStyle(.secondary)
                        Text("Your conversations are automatically saved as you chat.")
                            .font(.subheadline).foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(chatHistory.sessions) { session in
                                ChatHistoryRow(
                                    session: session,
                                    isCurrent: session.id == vm.currentSessionID,
                                    dateText: Self.dateFormatter.string(from: session.date),
                                    onOpen: {
                                        vm.loadSession(session)
                                        dismiss()
                                    },
                                    onDelete: {
                                        if session.id == vm.currentSessionID {
                                            vm.discardCurrentConversation()
                                        }
                                        chatHistory.delete(sessionID: session.id)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 36)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .hokieScreenBackground()
            .safeAreaInset(edge: .top) {
                HokieSheetHeader(
                    title: "Chat History",
                    subtitle: "\(chatHistory.sessions.count) saved conversation\(chatHistory.sessions.count == 1 ? "" : "s")",
                    symbol: "clock.arrow.circlepath",
                    accent: .vtBurgundy
                ) {
                    HStack(spacing: 8) {
                        Button {
                            vm.clearConversation()
                            dismiss()
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 13, weight: .black))
                                .frame(width: 34, height: 34)
                                .glassCircle(strokeOpacity: 0.08)
                        }
                        .accessibilityLabel("New chat")
                        .buttonStyle(.plain)

                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .black))
                                .frame(width: 34, height: 34)
                                .glassCircle(strokeOpacity: 0.08)
                        }
                        .accessibilityLabel("Close")
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(Color.vtBurgundy)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .transparentNavigationChrome()
        }
    }
}

private struct ChatHistoryRow: View {
    let session: ChatSession
    let isCurrent: Bool
    let dateText: String
    let onOpen: () -> Void
    let onDelete: () -> Void

    private var userMessageCount: Int {
        session.messages.filter { $0.role == "user" }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    HokieIconTile(
                        symbol: isCurrent ? "checkmark.bubble.fill" : "text.bubble.fill",
                        color: isCurrent ? .vtBurgundy : .vtOrange,
                        size: 40
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.title)
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            Text(dateText)
                            Text("/")
                            Text("\(userMessageCount) \(userMessageCount == 1 ? "message" : "messages")")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.red.opacity(0.82))
                    .frame(width: 34, height: 34)
                    .glassCircle(strokeOpacity: 0.08)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete chat")
        }
        .padding(14)
        .glassSurface(cornerRadius: 22)
    }
}

#Preview { ChatView().environmentObject(AppState()).environmentObject(ChatHistoryStore()) }
