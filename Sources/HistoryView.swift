import SwiftUI

struct PanelActions {
    let paste: (ClipItem, Bool) -> Void
    let remove: (ClipItem) -> Void
    let togglePin: (ClipItem) -> Void
    let clearAll: () -> Void
}

struct HistoryView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var model: PanelModel
    let actions: PanelActions
    @FocusState private var searchFocused: Bool
    @State private var hoveredID: UUID?

    var body: some View {
        let items = model.visible
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    list(items)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().opacity(0.6)
            footer
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .frame(width: PanelController.size.width, height: PanelController.size.height)
        .ignoresSafeArea()
        .onReceive(model.$focusToken) { _ in
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    // MARK: En-tête

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Rechercher dans le presse-papiers", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 4) {
                ForEach(PanelModel.Filter.allCases) { f in
                    FilterChip(title: f.rawValue, selected: model.filter == f) { model.filter = f }
                }
                Spacer()
                Text("\(store.items.count) élément\(store.items.count > 1 ? "s" : "")")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: Liste

    private func list(_ items: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipRow(item: item,
                                index: index,
                                selected: item.id == (model.selectedID ?? items.first?.id),
                                hovered: hoveredID == item.id,
                                store: store)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onHover { inside in
                                if inside { hoveredID = item.id } else if hoveredID == item.id { hoveredID = nil }
                            }
                            .onTapGesture { actions.paste(item, false) }
                            .contextMenu { contextMenu(for: item) }
                    }
                }
                .padding(6)
            }
            .onChange(of: model.selectedID) { id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
        Button("Coller") { actions.paste(item, false) }
        if item.kind != .image {
            Button("Coller en texte brut") { actions.paste(item, true) }
        }
        Divider()
        Button(item.pinned ? "Désépingler" : "Épingler") { actions.togglePin(item) }
        Button("Supprimer", role: .destructive) { actions.remove(item) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "Rien de copié pour l'instant" : "Aucun résultat")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if model.query.isEmpty {
                Text("Copiez du texte ou une image avec ⌘C,\nils apparaîtront ici.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Pied

    private var footer: some View {
        HStack(spacing: 10) {
            KeyHint(key: "↩", label: "Coller")
            KeyHint(key: "⇧↩", label: "Texte brut")
            KeyHint(key: "⌘P", label: "Épingler")
            KeyHint(key: "⌘⌫", label: "Suppr.")
            Spacer()
            Button(action: actions.clearAll) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Effacer l'historique (sauf les éléments épinglés)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Composants

struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(label)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
    }
}

struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let hovered: Bool
    let store: ClipboardStore

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            leadingIcon
            VStack(alignment: .leading, spacing: 4) {
                content
                meta
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(45))
                        .foregroundStyle(selected ? Color.white : Color.orange)
                }
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor : (hovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .foregroundStyle(selected ? Color.white : Color.primary)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        Group {
            if item.kind == .files, let first = item.filePaths?.first {
                Image(nsImage: IconCache.fileIcon(first)).resizable()
            } else if let app = IconCache.app(item.sourceBundleID) {
                Image(nsImage: app.icon).resizable()
            } else {
                Image(systemName: item.kind == .image ? "photo" : "doc.plaintext")
                    .font(.system(size: 14))
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
            }
        }
        .frame(width: 24, height: 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image:
            if let thumb = IconCache.thumbnail(for: item, store: store) {
                Image(nsImage: thumb)
                    .resizable()
                    .frame(width: fitted(thumb.size).width, height: fitted(thumb.size).height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Image").font(.system(size: 13))
            }
        case .text, .files:
            Text(item.preview)
                .font(.system(size: 13))
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fitted(_ size: NSSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 90, height: 90) }
        let scale = min(230 / size.width, 90 / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private var meta: some View {
        var parts: [String] = []
        if let name = IconCache.app(item.sourceBundleID)?.name { parts.append(name) }
        switch item.kind {
        case .image:
            if let w = item.imageWidth, let h = item.imageHeight { parts.append("\(w) × \(h)") }
        case .files:
            let n = item.filePaths?.count ?? 0
            parts.append("\(n) fichier\(n > 1 ? "s" : "")")
        case .text:
            let n = item.text?.count ?? 0
            if n > 600 { parts.append("\(n) caractères") }
        }
        let age = Date().timeIntervalSince(item.date)
        parts.append(age < 10 ? "à l'instant" : Self.relative.localizedString(for: item.date, relativeTo: Date()))
        return Text(parts.joined(separator: " · "))
            .font(.system(size: 10.5))
            .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
            .lineLimit(1)
    }
}
