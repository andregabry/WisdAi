import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DesktopSpace: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var workspace: Workspace
    @ObservedObject var local: DesktopLocalData
    @Binding var page: DesktopPage
    @State private var tab = "Sugestões"
    @State private var scope = "Tudo"
    @State private var query = ""
    @State private var grid = true
    @State private var sidebarVisible = true
    @State private var selected: Set<UUID> = []
    @State private var folderID: UUID?
    @State private var showFolder = false
    @State private var folderName = ""
    @State private var showActivity = false
    @State private var showShare = false
    @State private var favoritesOnly = false
    @State private var showCreatePopover = false
    @State private var actionMenuEntryID: UUID? = nil
    @AppStorage("wisdcode.spaceSidebarWidth") private var sidebarWidth: Double = 288

    private let tabs = ["Sugestões", "Páginas", "Slides", "Planilhas", "Imagens", "Sites"]
    private var title: String { local.spaces.first { $0.id == folderID }?.name ?? scope }

    private var entries: [LibraryEntry] {
        guard scope != "Compartilhados com você" else { return [] }
        let source = tab == "Sites" ? local.sites : tab == "Sugestões" ? local.library + local.sites : local.library
        return source.filter { entry in
            let inTrash = local.libraryTrash.contains(entry.id)
            let inFolder = folderID == nil || local.spaces.first { $0.id == folderID }?.members.contains(entry.id) == true
            return (scope == "Lixeira" ? inTrash : !inTrash) && inFolder && (!favoritesOnly || entry.favorite) &&
                (query.isEmpty || entry.url.lastPathComponent.localizedCaseInsensitiveContains(query)) &&
                (tab == "Sugestões" || tab == "Sites" || kind(entry) == tab)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let maxSidebar = max(190.0, min(460.0, Double(geo.size.width) - 420.0 - 6.0))
            let clampedSidebar = min(maxSidebar, max(190.0, sidebarWidth))

            HStack(spacing: 0) {
                if sidebarVisible {
                    sidebar(width: CGFloat(clampedSidebar))
                        .zIndex(2)
                    WisdSplitHandle(
                        width: $sidebarWidth,
                        minWidth: 190,
                        maxWidth: maxSidebar,
                        defaultWidth: 288
                    )
                    .zIndex(5)
                }
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        if !sidebarVisible {
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible = true }
                            } label: { Image(systemName: "sidebar.left") }
                                .accessibilityLabel("Mostrar barra lateral")
                        }
                        Text(title).font(.system(size: 25, weight: .medium))
                        Spacer()
                        DesktopSearchField(title: tab == "Sites" ? "Pesquisar sites" : "Pesquisar no Espaço", text: $query).frame(maxWidth: 270)
                    }
                HStack(spacing: 4) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            ForEach(tabs, id: \.self) { item in
                                Button { tab = item; selected = [] } label: {
                                    Text(item).font(.system(size: 14, weight: .regular)).padding(.horizontal, 16).frame(height: 36)
                                        .background(tab == item ? DesktopStyle.surface : .clear, in: Capsule())
                                }.accessibilityAddTraits(tab == item ? .isSelected : [])
                            }
                        }
                    }.scrollIndicators(.hidden)
                    Spacer(minLength: 8)
                    Button { favoritesOnly.toggle(); selected = [] } label: {
                        Image(systemName: favoritesOnly ? "star.fill" : "star").frame(width: 34, height: 34)
                            .modifier(DesktopHover(selected: favoritesOnly, radius: 17))
                    }.accessibilityLabel("Filtrar favoritos")
                    Button { grid = true } label: {
                        Image(systemName: "square.grid.2x2").frame(width: 34, height: 34).modifier(DesktopHover(selected: grid, radius: 17))
                    }.accessibilityLabel("Visualização em grade")
                    Button { grid = false } label: {
                        Image(systemName: "list.bullet").frame(width: 34, height: 34).modifier(DesktopHover(selected: !grid, radius: 17))
                    }.accessibilityLabel("Visualização em lista")
                }
                if !selected.isEmpty { selectionToolbar }
                if entries.isEmpty {
                    emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        if grid { fileGrid } else { fileList }
                    }.scrollIndicators(.hidden)
                }
            }.padding(32).frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity).clipped().zIndex(0)
            }
        }
        .background(DesktopStyle.canvas)
        .onChange(of: page, initial: true) {
            tab = page == .sites ? "Sites" : page == .images ? "Imagens" : "Sugestões"
            selected = []
        }
        .sheet(isPresented: $showFolder) {
            folderEditor
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $showShare) {
            WisdModalShell(
                title: "Compartilhar",
                subtitle: "Biblioteca local neste Mac",
                statusColor: WisdTheme.iconAccent,
                width: 420,
                onClose: { showShare = false },
                footer: {
                    HStack {
                        Spacer()
                        WisdPrimaryButton("Concluído") { showShare = false }
                    }
                }
            ) {
                Text("O compartilhamento entre contas ainda precisa de integração. Estes itens estão na biblioteca local deste Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(WisdTheme.ink(scheme))
            }
            .presentationBackground(.clear)
        }
    }

    private func sidebar(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Text("Espaço").font(.system(size: 19, weight: .semibold))
                Spacer()
                Button { showActivity.toggle() } label: { Image(systemName: "bell") }.accessibilityLabel("Atividade")
                    .popover(isPresented: $showActivity) {
                        WisdPopoverShell(
                            title: "Atividade",
                            subtitle: "Biblioteca local",
                            statusColor: local.library.isEmpty ? WisdTheme.muted(scheme) : WisdTheme.success,
                            width: 280
                        ) {
                            Text(local.library.isEmpty ? "Ainda não há atividade local." : "\(local.library.count) itens na biblioteca local.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(WisdTheme.muted(scheme))
                                .padding(16)
                        }
                        .presentationBackground(.clear)
                    }
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible = false }
                } label: { Image(systemName: "sidebar.left") }.accessibilityLabel("Alternar barra lateral")
            }.padding(.horizontal, 10).frame(height: 42)
            createMenu.padding(.horizontal, 10).padding(.bottom, 10)
            sidebarLink("Tudo", icon: "rectangle.on.rectangle")
            sidebarLink("Seus itens", icon: "person")
            sidebarLink("Compartilhados com você", icon: "person.2")
            HStack {
                Text("Espaços").foregroundStyle(DesktopStyle.muted)
                Spacer()
                Button { folderName = ""; showFolder = true } label: { Image(systemName: "plus") }.accessibilityLabel("Novo espaço")
            }.padding(.horizontal, 12).padding(.top, 24)
            ForEach(local.spaces) { folder in
                Button { folderID = folder.id; scope = "Tudo"; selected = [] } label: {
                    Label(folder.name, systemImage: "folder").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10).modifier(DesktopHover(selected: folderID == folder.id))
                }
            }
            Text("Recentes").foregroundStyle(DesktopStyle.muted).padding(.horizontal, 12).padding(.top, 24)
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(local.library.filter { !local.libraryTrash.contains($0.id) }.suffix(6).reversed()) { entry in
                        Button { NSWorkspace.shared.open(entry.url) } label: {
                            Label(entry.url.lastPathComponent, systemImage: symbol(entry)).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(10).modifier(DesktopHover())
                        }
                    }
                }
            }.scrollIndicators(.hidden)
            Spacer(minLength: 0)
            sidebarLink("Lixeira", icon: "trash")
        }.padding(12).frame(width: width).clipped()
    }

    private func sidebarLink(_ title: String, icon: String) -> some View {
        Button { scope = title; folderID = nil; selected = [] } label: {
            Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .modifier(DesktopHover(selected: scope == title && folderID == nil))
        }
    }

    private var createMenu: some View {
        Button {
            showCreatePopover.toggle()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                Text("Criar")
                Image(systemName: "chevron.down").font(.system(size: 10))
            }
            .padding(.horizontal, 15).frame(height: 36)
            .background(DesktopStyle.surface, in: Capsule())
            .overlay(Capsule().stroke(showCreatePopover ? WisdTheme.accent.opacity(0.6) : DesktopStyle.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showCreatePopover, arrowEdge: .bottom) {
            WisdPopoverShell(
                title: "Criar ou Importar",
                subtitle: "Documentos, sites e organização",
                statusColor: WisdTheme.iconAccent,
                width: 270
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    WisdPopoverSection("Gerar no Chat") {
                        VStack(spacing: 2) {
                            WisdSelectableRow(icon: "doc", title: "Página") {
                                showCreatePopover = false; createInChat("Crie uma página Markdown neste projeto com o seguinte conteúdo: ")
                            }
                            WisdSelectableRow(icon: "rectangle.on.rectangle", title: "Apresentação") {
                                showCreatePopover = false; createInChat("Crie uma apresentação neste projeto sobre: ")
                            }
                            WisdSelectableRow(icon: "tablecells", title: "Planilha") {
                                showCreatePopover = false; createInChat("Crie uma planilha neste projeto para: ")
                            }
                            WisdSelectableRow(icon: "photo", title: "Imagem") {
                                showCreatePopover = false; createInChat("Ajude a preparar uma imagem para este projeto com os seguintes requisitos: ")
                            }
                            WisdSelectableRow(icon: "square.grid.2x2", title: "Site") {
                                showCreatePopover = false; createInChat("Crie um site neste projeto. Requisitos: ", site: true)
                            }
                        }
                        .padding(.horizontal, 10)
                    }

                    Rectangle().fill(WisdTheme.divider(scheme)).frame(height: 1)

                    WisdPopoverSection {
                        VStack(spacing: 2) {
                            WisdSelectableRow(icon: "arrow.up.doc", title: "Importar arquivos") {
                                showCreatePopover = false; importFiles()
                            }
                            WisdSelectableRow(icon: "folder.badge.plus", title: "Novo espaço") {
                                showCreatePopover = false; folderName = ""; showFolder = true
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                    }
                }
            }
            .presentationBackground(.clear)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: scope == "Lixeira" ? "trash" : tab == "Sites" ? "square.grid.2x2" : tab == "Imagens" ? "photo" : "doc.on.doc")
                .font(.system(size: 30)).foregroundStyle(DesktopStyle.muted)
            Text(!query.isEmpty ? "Nenhum resultado encontrado" : favoritesOnly ? "Nenhum favorito nesta visualização" : scope == "Lixeira" ? "A lixeira está vazia" : scope == "Compartilhados com você" ? "Nenhum item compartilhado" : "Ainda não há \(tab == "Sites" ? "sites" : tab == "Imagens" ? "imagens" : "itens")")
                .font(.system(size: 20))
            if scope == "Compartilhados com você" {
                Text("O compartilhamento entre contas ainda precisa de integração.").foregroundStyle(DesktopStyle.muted)
            } else if scope != "Lixeira" && query.isEmpty && !favoritesOnly {
                Button(tab == "Sites" ? "Criar site" : "Importar arquivos", systemImage: "plus") {
                    if tab == "Sites" { createInChat("Crie um site neste projeto. Requisitos: ", site: true) }
                    else { importFiles() }
                }.padding(.horizontal, 16).padding(.vertical, 10)
                    .overlay(Capsule().strokeBorder(DesktopStyle.line))
            }
        }.padding(30).multilineTextAlignment(.center)
    }

    private var fileGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 18)], spacing: 18) {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button { toggleSelection(entry.id) } label: {
                            Image(systemName: selected.contains(entry.id) ? "checkmark.circle.fill" : symbol(entry))
                        }.accessibilityLabel("Selecionar \(entry.url.lastPathComponent)")
                        Text(entry.url.lastPathComponent).lineLimit(1).font(.system(size: 12))
                        Spacer(minLength: 2)
                        fileActionMenuButton(for: entry, width: nil)
                    }.padding(12)
                    Divider()
                    Button { NSWorkspace.shared.open(entry.url) } label: {
                        Group {
                            if entry.isImage, let image = NSImage(contentsOf: entry.url) {
                                Image(nsImage: image).resizable().scaledToFit().padding(10)
                            } else {
                                VStack(spacing: 10) {
                                    Image(systemName: symbol(entry)).font(.system(size: 40, weight: .light))
                                    Text(entry.url.pathExtension.uppercased()).font(.system(size: 13, weight: .medium))
                                }.foregroundStyle(entry.url.pathExtension.lowercased() == "pdf" ? Color.red : DesktopStyle.muted)
                            }
                        }.frame(maxWidth: .infinity).frame(height: 170)
                    }
                    HStack {
                        Text("Você").font(.system(size: 11)).foregroundStyle(DesktopStyle.muted)
                        Spacer()
                        Button { toggleFavorite(entry.id) } label: { Image(systemName: entry.favorite ? "star.fill" : "star") }
                            .accessibilityLabel(entry.favorite ? "Remover favorito" : "Favoritar")
                    }.padding(12)
                }
                .background(DesktopStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected.contains(entry.id) ? DesktopStyle.accent : DesktopStyle.line))
                .contextMenu { fileActions(entry) }
            }
        }
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Nome").frame(maxWidth: .infinity, alignment: .leading)
                Text("Proprietário").frame(width: 75, alignment: .leading)
                Color.clear.frame(width: 28)
            }.font(.system(size: 12)).foregroundStyle(DesktopStyle.muted).padding(12)
            Divider()
            ForEach(entries) { entry in
                HStack(spacing: 12) {
                    Button { toggleSelection(entry.id) } label: { Image(systemName: selected.contains(entry.id) ? "checkmark.square.fill" : "square") }
                        .accessibilityLabel("Selecionar \(entry.url.lastPathComponent)")
                    Image(systemName: symbol(entry)).foregroundStyle(DesktopStyle.muted)
                    VStack(alignment: .leading, spacing: 5) {
                        Button(entry.url.lastPathComponent) { NSWorkspace.shared.open(entry.url) }.lineLimit(1)
                        Text(modified(entry)).font(.system(size: 11)).foregroundStyle(DesktopStyle.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text("Você").frame(width: 75, alignment: .leading).foregroundStyle(DesktopStyle.muted)
                    fileActionMenuButton(for: entry, width: 28)
                }.font(.system(size: 13)).padding(12).modifier(DesktopHover(selected: selected.contains(entry.id)))
                    .contextMenu { fileActions(entry) }
                Divider()
            }
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 18) {
            Text("\(selected.count) selecionado(s)").foregroundStyle(DesktopStyle.muted)
            Button("Compartilhar", systemImage: "person.badge.plus") { showShare = true }
            Button(scope == "Lixeira" ? "Restaurar" : "Mover para lixeira", systemImage: scope == "Lixeira" ? "arrow.uturn.backward" : "trash") {
                for id in selected {
                    if scope == "Lixeira" { local.libraryTrash.removeAll { $0 == id } }
                    else if !local.libraryTrash.contains(id) { local.libraryTrash.append(id) }
                }
                selected = []
            }
            Spacer()
            Button("Cancelar") { selected = [] }
        }.font(.system(size: 12)).padding(12).background(DesktopStyle.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func fileActions(_ entry: LibraryEntry) -> some View {
        Button("Abrir") { NSWorkspace.shared.open(entry.url) }
        if local.sites.contains(where: { $0.id == entry.id }), FileManager.default.fileExists(atPath: entry.url.appendingPathComponent("index.html").path) {
            Button("Prévia") { NSWorkspace.shared.open(entry.url.appendingPathComponent("index.html")) }
        }
        Button(entry.favorite ? "Remover favorito" : "Favoritar") { toggleFavorite(entry.id) }
        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        if !local.spaces.isEmpty {
            Menu("Adicionar ao espaço") {
                ForEach(local.spaces) { folder in
                    Button(folder.name) {
                        guard let index = local.spaces.firstIndex(where: { $0.id == folder.id }) else { return }
                        if !local.spaces[index].members.contains(entry.id) { local.spaces[index].members.append(entry.id) }
                    }
                }
            }
        }
        Button("Compartilhar") { showShare = true }
        Divider()
        Button(scope == "Lixeira" ? "Restaurar" : "Mover para lixeira") {
            if scope == "Lixeira" { local.libraryTrash.removeAll { $0 == entry.id } }
            else if !local.libraryTrash.contains(entry.id) { local.libraryTrash.append(entry.id) }
        }
    }

    private func fileActionMenuButton(for entry: LibraryEntry, width: CGFloat?) -> some View {
        Button {
            actionMenuEntryID = entry.id
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: width ?? 22, height: 22)
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: Binding(
                get: { actionMenuEntryID == entry.id },
                set: { if !$0 && actionMenuEntryID == entry.id { actionMenuEntryID = nil } }
            ),
            arrowEdge: .bottom
        ) {
            WisdPopoverShell(
                title: entry.url.lastPathComponent,
                subtitle: kind(entry),
                statusColor: WisdTheme.iconAccent,
                width: 270
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    WisdPopoverSection {
                        VStack(spacing: 2) {
                            WisdSelectableRow(icon: "arrow.up.right.square", title: "Abrir") {
                                actionMenuEntryID = nil; NSWorkspace.shared.open(entry.url)
                            }
                            if local.sites.contains(where: { $0.id == entry.id }),
                               FileManager.default.fileExists(atPath: entry.url.appendingPathComponent("index.html").path) {
                                WisdSelectableRow(icon: "eye", title: "Prévia") {
                                    actionMenuEntryID = nil; NSWorkspace.shared.open(entry.url.appendingPathComponent("index.html"))
                                }
                            }
                            WisdSelectableRow(icon: entry.favorite ? "star.slash" : "star", title: entry.favorite ? "Remover favorito" : "Favoritar") {
                                actionMenuEntryID = nil; toggleFavorite(entry.id)
                            }
                            WisdSelectableRow(icon: "folder", title: "Mostrar no Finder") {
                                actionMenuEntryID = nil; NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                            }
                            WisdSelectableRow(icon: "person.badge.plus", title: "Compartilhar") {
                                actionMenuEntryID = nil; showShare = true
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                    }

                    if !local.spaces.isEmpty {
                        Rectangle().fill(WisdTheme.divider(scheme)).frame(height: 1)
                        WisdPopoverSection("Adicionar ao espaço") {
                            VStack(spacing: 2) {
                                ForEach(local.spaces) { folder in
                                    let isMember = folder.members.contains(entry.id)
                                    WisdSelectableRow(icon: "folder.badge.plus", title: folder.name, selected: isMember) {
                                        if let index = local.spaces.firstIndex(where: { $0.id == folder.id }),
                                           !local.spaces[index].members.contains(entry.id) {
                                            local.spaces[index].members.append(entry.id)
                                        }
                                        actionMenuEntryID = nil
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                        }
                    }

                    Rectangle().fill(WisdTheme.divider(scheme)).frame(height: 1)
                    WisdPopoverSection {
                        VStack(spacing: 2) {
                            WisdSelectableRow(
                                icon: scope == "Lixeira" ? "arrow.uturn.backward" : "trash",
                                iconColor: scope == "Lixeira" ? WisdTheme.iconAccent : WisdTheme.danger,
                                title: scope == "Lixeira" ? "Restaurar" : "Mover para lixeira"
                            ) {
                                actionMenuEntryID = nil
                                if scope == "Lixeira" { local.libraryTrash.removeAll { $0 == entry.id } }
                                else if !local.libraryTrash.contains(entry.id) { local.libraryTrash.append(entry.id) }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                    }
                }
            }
            .presentationBackground(.clear)
        }
    }

    private var folderEditor: some View {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return WisdModalShell(
            title: "Novo espaço",
            subtitle: "Agrupe documentos, imagens e sites locais",
            statusColor: WisdTheme.iconAccent,
            width: 420,
            onClose: { showFolder = false },
            footer: {
                HStack(spacing: 10) {
                    Spacer()
                    WisdSecondaryButton("Cancelar") { showFolder = false }
                        .keyboardShortcut(.cancelAction)
                    WisdPrimaryButton("Criar", icon: "folder.badge.plus", disabled: trimmed.isEmpty) {
                        let folder = LocalSpaceFolder(name: trimmed)
                        local.spaces.append(folder); folderID = folder.id; scope = "Tudo"; showFolder = false
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nome do espaço")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(WisdTheme.muted(scheme))
                TextField("Ex: Referências, Protótipos…", text: $folderName)
                    .wisdFieldSurface(focused: true)
            }
        }
    }

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else {
            workspace.error = "Não foi possível abrir o seletor de arquivos nesta janela."
            return
        }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            completeImport(panel.urls)
        }
    }

    private func completeImport(_ urls: [URL]) {
        for url in urls {
            if let existing = local.library.first(where: { $0.path == url.path }) {
                local.libraryTrash.removeAll { $0 == existing.id }
            } else { local.library.append(LibraryEntry(path: url.path)) }
        }
        tab = "Sugestões"; scope = "Seus itens"; folderID = nil
    }

    private func createInChat(_ prompt: String, site: Bool = false) {
        guard !workspace.busy else { return }
        if workspace.project == nil { workspace.chooseProject() }
        guard let project = workspace.project else { return }
        if site, !local.sites.contains(where: { $0.path == project.path }) { local.sites.append(LibraryEntry(path: project.path)) }
        workspace.newConversation(); workspace.prompt = prompt; page = .chat
    }

    private func toggleSelection(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func toggleFavorite(_ id: UUID) {
        if let index = local.library.firstIndex(where: { $0.id == id }) { local.library[index].favorite.toggle() }
        else if let index = local.sites.firstIndex(where: { $0.id == id }) { local.sites[index].favorite.toggle() }
    }

    private func kind(_ entry: LibraryEntry) -> String {
        if entry.isImage { return "Imagens" }
        if ["ppt", "pptx", "key"].contains(entry.url.pathExtension.lowercased()) { return "Slides" }
        if ["csv", "xls", "xlsx", "numbers"].contains(entry.url.pathExtension.lowercased()) { return "Planilhas" }
        return "Páginas"
    }

    private func symbol(_ entry: LibraryEntry) -> String {
        if entry.isFolder { return "folder" }
        switch kind(entry) {
        case "Imagens": return "photo"
        case "Slides": return "rectangle.on.rectangle"
        case "Planilhas": return "tablecells"
        default: return "doc.text"
        }
    }

    private func modified(_ entry: LibraryEntry) -> String {
        guard let date = try? entry.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
