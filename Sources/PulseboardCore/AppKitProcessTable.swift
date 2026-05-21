import AppKit
import SwiftUI

public struct ProcessTableView: NSViewRepresentable {
    public var processes: [ProcessMetric]
    public var columns: [ColumnConfig]
    public var density: DisplayDensity
    public var sort: ProcessSort
    @Binding public var selectedPID: Int32?
    public var onSort: (ProcessSort) -> Void

    public init(
        processes: [ProcessMetric],
        columns: [ColumnConfig],
        density: DisplayDensity,
        sort: ProcessSort,
        selectedPID: Binding<Int32?>,
        onSort: @escaping (ProcessSort) -> Void
    ) {
        self.processes = processes
        self.columns = columns
        self.density = density
        self.sort = sort
        self._selectedPID = selectedPID
        self.onSort = onSort
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tableView = NSTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.headerView = NSTableHeaderView()
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.selectionHighlightStyle = .regular
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.rowHeight = density.rowHeight

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.syncColumns()
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = context.coordinator.tableView ?? scrollView.documentView as? NSTableView else { return }
        context.coordinator.tableView = tableView
        tableView.rowHeight = density.rowHeight
        context.coordinator.syncColumns()
        tableView.reloadData()

        if let selectedPID, let row = processes.firstIndex(where: { $0.pid == selectedPID }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else if selectedPID == nil {
            tableView.deselectAll(nil)
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: ProcessTableView
        weak var tableView: NSTableView?

        init(parent: ProcessTableView) {
            self.parent = parent
        }

        public func numberOfRows(in tableView: NSTableView) -> Int {
            parent.processes.count
        }

        public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard
                row < parent.processes.count,
                let tableColumn,
                let processColumn = ProcessColumn(rawValue: tableColumn.identifier.rawValue)
            else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("cell-\(processColumn.rawValue)")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? makeCell(identifier: identifier, column: processColumn)
            cell.textField?.stringValue = parent.processes[row].valueText(for: processColumn)
            cell.textField?.alignment = alignment(for: processColumn)
            return cell
        }

        public func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let row = tableView.selectedRow
            guard row >= 0, row < parent.processes.count else {
                parent.selectedPID = nil
                return
            }
            parent.selectedPID = parent.processes[row].pid
        }

        public func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key, let column = ProcessColumn(rawValue: key) else {
                return
            }
            parent.onSort(ProcessSort(column: column, ascending: descriptor.ascending))
        }

        func syncColumns() {
            guard let tableView else { return }
            let expected = parent.columns.map { $0.id.rawValue }
            let current = tableView.tableColumns.map { $0.identifier.rawValue }

            guard expected != current else {
                applySortDescriptor()
                return
            }

            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }

            for config in parent.columns {
                let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(config.id.rawValue))
                tableColumn.title = config.id.title
                tableColumn.width = config.width
                tableColumn.minWidth = min(64, max(48, config.width * 0.5))
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: config.id.rawValue, ascending: true)
                tableView.addTableColumn(tableColumn)
            }

            applySortDescriptor()
        }

        private func applySortDescriptor() {
            guard let tableView else { return }
            let descriptor = NSSortDescriptor(key: parent.sort.column.rawValue, ascending: parent.sort.ascending)
            if tableView.sortDescriptors != [descriptor] {
                tableView.sortDescriptors = [descriptor]
            }
        }

        private func makeCell(identifier: NSUserInterfaceItemIdentifier, column: ProcessColumn) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            textField.lineBreakMode = column == .path ? .byTruncatingMiddle : .byTruncatingTail
            textField.maximumNumberOfLines = 1

            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])

            return cell
        }

        private func alignment(for column: ProcessColumn) -> NSTextAlignment {
            switch column {
            case .pid, .cpu, .memory, .threads, .user:
                .right
            case .name, .path:
                .left
            }
        }
    }
}
