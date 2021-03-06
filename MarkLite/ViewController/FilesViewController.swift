//
//  FilesViewController.swift
//  Markdown
//
//  Created by zhubch on 2017/6/22.
//  Copyright © 2017年 zhubch. All rights reserved.
//

import UIKit
import EZSwiftExtensions
import RxSwift
import QuickLook
import Zip

class FilesViewController: UIViewController {
        
    @IBOutlet weak var tableView: UITableView!
    
    @IBOutlet weak var deleteButton: UIButton!
    
    @IBOutlet weak var moveButton: UIButton!
    
    @IBOutlet weak var sendButton: UIButton!

    @IBOutlet weak var emptyView: UIView!

    @IBOutlet weak var bottomBar: UIView!
    
    @IBOutlet weak var bottomBarOffset: NSLayoutConstraint!

    fileprivate var files = [File]()
    
    fileprivate var items = [
        File.cloud,
        File.inbox,
//        File.webdav,
    ]
    
    var sections: [[File]] {
        if isHomePage {
            return [items,files]
        }
        return [files]
    }
    
    var root = File.empty
    
    let bag = DisposeBag()
            
    var textField: UITextField?
    
    var isHomePage = false
    
    var selectFolderMode = false
    
    var selectFiles = [File]()
    
    var selectedFolder: File?
    
    var filesToMove: [File]?

    var moveFrom: FilesViewController?
    
    var previewingFile: File?
    
    let searchBar = UISearchBar()
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return Configure.shared.theme.value == .white ? .default : .lightContent
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if root == File.empty && selectFolderMode == false {
            root = File.local
            isHomePage = true
        }
        
        if isHomePage {
            title = /"Documents"
            loadFiles()
            observeChanges()
        } else if selectFolderMode {
            title = /"MoveTo"
            File.local.expand = false
            File.cloud.expand = false
            _ = Configure.shared.theme.asObservable().subscribe(onNext: { (theme) in
                self.navBar?.barStyle = theme == .white ? .default : .black
            })
        } else {
            title = root.displayName
            tableView.tableHeaderView = UIView(x: 0, y: 0, w: 0, h: 0.01)
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(proStatusChanged(_:)), name: Notification.Name("DisplayOptionChanged"), object: nil)
        
        refresh()

        setupUI()
        
        setupBarButton()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if !isMovingToParentViewController && !selectFolderMode {
            refresh()
        }
        
        if root == File.cloud {
            root.reloadChildren()
            refresh()
        }
        
        tableView.allowsMultipleSelectionDuringEditing = false
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        searchBar.resignFirstResponder()
    }
    
    deinit {
        print(self)
        NotificationCenter.default.removeObserver(self)
    }
    
    func observeChanges() {
        NotificationCenter.default.addObserver(self, selector: #selector(localChanged(_:)), name: Notification.Name("LocalChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(recievedNewFile(_:)), name: Notification.Name("RecievedNewFile"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(proStatusChanged(_:)), name: Notification.Name("PremiumStatusChanged"), object: nil)
    }
    
    func loadFiles() {
        File.loadLocal { local in
            self.root = local
            self.refresh()
        }
        File.loadCloud { cloud in
            self.items[0] = cloud
            self.tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .none)
        }
        File.loadInbox { inbox in
            self.items[1] = inbox
            self.tableView.reloadRows(at: [IndexPath(row: 1, section: 0)], with: .none)
        }
    }
    
    @objc func proStatusChanged(_ noti: Notification) {
        tableView.reloadData()
    }
    
    @objc func displayOptionChanged(_ noti: Notification) {
        tableView.reloadData()
    }
    
    @objc func localChanged(_ noti: Notification) {
        navigationController?.popToRootViewController(animated: true)
        File.loadLocal { local in
            self.root = local
            self.refresh()
        }
    }
    
    @objc func recievedNewFile(_ noti: Notification) {
        navigationController?.popToRootViewController(animated: true)
        guard let url = noti.object as? URL else { return }
        File.local.reloadChildren()
        accessFile(url)
    }
    
    @objc func multipleSelect() {
        selectFiles = []
        
        let selected = selectFiles.count > 0
        moveButton.isEnabled = selected
        sendButton.isEnabled = selected
        deleteButton.isEnabled = selected
        tableView.setEditing(tableView.isEditing == false, animated: true)
        setupBarButton()
        if root == File.inbox {
            return
        }
        bottomBar.isHidden = tableView.isEditing
        UIView.animate(withDuration: 0.5) {
            self.view.layoutIfNeeded()
        }
    }
    
    @objc func selectAllFiles() {
        impactIfAllow()
        for i in 0..<files.count {
            selectFiles.append(files[i])
            let indexPath = IndexPath(row: i, section: isHomePage ? 1 : 0)
            tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
        }
        let selected = selectFiles.count > 0
        moveButton.isEnabled = selected
        sendButton.isEnabled = selected
        deleteButton.isEnabled = selected
    }
    
    func refresh() {
        if (selectFolderMode) {
            files = [File.cloud,File.local]
        } else {
            files = root.children.filter {
                return (self.searchBar.text?.count ?? 0) == 0 || $0.displayName.contains(self.searchBar.text!)
            }.sorted {
                switch Configure.shared.sortOption {
                case .type:
                    return $0.type == .text && $1.type == .folder
                case .name:
                    return $0.name.localizedCompare($1.name) == .orderedAscending
                case .modifyDate:
                    return $0.modifyDate > $1.modifyDate
                }
            }
        }
        if isViewLoaded {
            tableView.reloadData()
            if selectFolderMode || tableView.isEditing || (splitViewController?.isCollapsed ?? false) {
                return
            }
            if let current = File.current, let index = files.firstIndex(where: { $0 == current }) {
                let indexPath = IndexPath(row: index, section: isHomePage ? 1 : 0)
                tableView.selectRow(at: indexPath, animated: false, scrollPosition: .middle)
            }
        }
    }
    
    @IBAction func longPressedTableView(_ ges: UILongPressGestureRecognizer!) {
        if ges.state != .began {
            return
        }
        if tableView.isEditing || selectFolderMode {
            return
        }
        if root.isExternalFile {
            return
        }
        let pos = ges.location(in: ges.view)
        if let _ = tableView.indexPathForRow(at: pos) {
            multipleSelect()
            impactIfAllow()
        }
    }
    
    @IBAction func moveFiles(_ sender: UIButton) {
        impactIfAllow()
        if self.selectFiles.count == 0 {
            return
        }
        self.performSegue(withIdentifier: "move", sender: self.selectFiles)
        multipleSelect()
    }
    
    @IBAction func sendFiles(_ sender: UIButton) {
        impactIfAllow()
        if self.selectFiles.count == 0 {
            return
        }
        let urls = self.selectFiles.mapFilter { return $0.url }
        let vc = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = sender
        vc.popoverPresentationController?.sourceRect = sender.superview!.convert(sender.frame, to: self.view)
        self.presentVC(vc)
    }
    
    @IBAction func deleteFiles(_ sender: UIButton) {
        impactIfAllow()
        if self.selectFiles.count == 0 {
            return
        }
        
        self.showDestructiveAlert(title: nil, message: /"DeleteMessage", actionTitle: /"Delete") {
            self.selectFiles.forEach { file in
                file.trash()
                if file == File.current  {
                    file.close()
                    self.editFile(nil)
                }
            }
            self.refresh()
            self.multipleSelect()
        }
    }
    
    @IBAction func searchFiles(_ sender: UIButton) {
        impactIfAllow()
        searchBar.superview?.isHidden = false
        searchBar.becomeFirstResponder()
    }
    
    @IBAction func beginEdit(_ sender: UIButton) {
        impactIfAllow()
        multipleSelect()
    }
    
    @IBAction func sortOptions(_ sender: UIButton) {
        impactIfAllow()
        let options = [SortOption.name,.type,.modifyDate]
        let alert = UIAlertController(title: /"SortOptions", message: nil, preferredStyle: isPad ? .alert : .actionSheet)
        options.forEach { option in
            let action = UIAlertAction(title: option.displayName, style: .default, handler: { action in
                Configure.shared.sortOption = option
                impactIfAllow()
                self.refresh()
            })
            action.isEnabled = Configure.shared.sortOption != option
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: /"Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    @objc func cancel() {
        impactIfAllow()
        dismiss(animated: true, completion: nil)
    }
    
    @objc func sureMove() {
        impactIfAllow()
        guard let newParent = selectedFolder else { return }
        filesToMove?.forEach { file in
            if file == File.current  {
                file.close()
                self.editFile(nil)
            }
            file.move(to: newParent)
        }
        moveFrom?.refresh()
        dismiss(animated: true)
    }
    
    @objc func showSettings() {
        impactIfAllow()
        performSegue(withIdentifier: "settings", sender: nil)
    }
    
    @objc func createFile(_ sender: Any) {
        impactIfAllow()
        showAlert(title: nil, message: /"CreateTips", actionTitles: [/"CreateNote",/"CreateFolder",/"Cancel"], textFieldconfigurationHandler: { textField in
            textField.clearButtonMode = .whileEditing
            textField.placeholder = /"FileNamePlaceHolder"
            self.textField = textField
        }) { index in
            let name = self.textField?.text ?? ""
            if name.count == 0 || index == 2 {
                return
            }
            if !name.isValidFileName {
                ActivityIndicator.showError(withStatus: /"FileNameError")
                return
            }
            guard let file = self.root.createFile(name: name, type: index == 0 ? .text : .folder) else {
                return
            }
            self.openFile(file)
        }
    }
    
    func openFile(_ file: File) {
        if file.type == .folder {
            performSegue(withIdentifier: "file", sender: file)
            return
        }
        if file.type == .archive {
            unzip(file)
            return
        }
        if file.type == .image || file.type == .other {
            preview(file)
            return
        }
        func openText() {
            print("file \(file.displayName) tap open")
            ActivityIndicator.show()
            file.open { success in
                ActivityIndicator.dismiss()
                if success {
                    self.editFile(file)
                } else {
                    self.editFile(nil)
                    ActivityIndicator.showError(withStatus: /"CanNotAccesseThisFile")
                }
            }
        }
        if file == File.current {
            if (splitViewController?.isCollapsed ?? false) == false {
                return
            } else {
                openText()
            }
        } else {
            File.current?.close()
            if !Configure.shared.showedTips.contains("4") {
                showAlert(title: /"Tips", message: /"FileOpenTips", actionTitles: [/"GotIt"], textFieldconfigurationHandler: nil) { _ in
                    openText()
                }
                Configure.shared.showedTips.append("4")
            } else {
                openText()
            }
        }
    }
    
    func editFile(_ file: File?) {
        if file == nil && (File.current == nil || isPad == false) {
            return
        }
        guard let parent = file?.parent else {
            self.performSegue(withIdentifier: "edit", sender: file)
            return
        }
        self.goToRoot(parent)
        self.performSegue(withIdentifier: "edit", sender: file)
    }
    
    func preview(_ file: File) {
        guard let url = file.url as NSURL?, QLPreviewController.canPreview(url) else {
            ActivityIndicator.showError(withStatus: /"CanNotPreviewThisFile")
            return
        }
        previewingFile = file
        let vc = QLPreviewController()
        vc.dataSource = self
        vc.modalPresentationStyle = .pageSheet
        vc.currentPreviewItemIndex = 0
        presentVC(vc)
    }
    
    func unzip(_ file: File) {
        guard let url = file.url, let destURL = root.url else { return }
        ActivityIndicator.show()
        DispatchQueue.global().async {
            do {
                try Zip.unzipFile(url, destination: destURL, overwrite: true, password: nil, progress: { progress in

                })
                DispatchQueue.main.async {
                    self.root.reloadChildren()
                    self.refresh()
                    ActivityIndicator.dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    ActivityIndicator.dismiss()
                    ActivityIndicator.showError(withStatus: /"UnzipFailed")
                }
            }
        }
    }
    
    func goToRoot(_ root: File) {
        guard root.type == .folder else {
            return
        }
        if root == self.root {
            refresh()
            return
        }
        if let vc = self.navigationController?.viewControllers.first(where: { vc -> Bool in
            if let filesVC = vc as? FilesViewController {
                return filesVC.root == root
            }
            return false
        }) {
            self.navigationController?.popToViewController(vc, animated: true)
            return
        }
        performSegue(withIdentifier: "file", sender: root)
    }
    
    func didSelectFile(_ indexPath: IndexPath) {
        let file = sections[indexPath.section][indexPath.row]
        if file == File.inbox && file.children.count == 0 {
            pickFromFiles()
            return
        }
        if file == File.webdav {
            return
        }
        if file.disable {
            ActivityIndicator.showError(withStatus: /"CanNotAccesseThisFile")
            return
        }
        
        openFile(file)
    }
    
    func didSelectDestFolder(_ indexPath: IndexPath) {
        navigationItem.rightBarButtonItem?.isEnabled = true
        selectedFolder = sections[indexPath.section][indexPath.row]
        let cell = tableView.cellForRow(at: indexPath)
        if selectedFolder!.folders.count > 0 {
            var indexPaths = [IndexPath]()
            if selectedFolder!.expand {
                files.removeAll { item -> Bool in
                    return selectedFolder!.visibleFolders.contains{ $0 == item }
                }
                for i in 1...selectedFolder!.visibleFolders.count {
                    indexPaths.append(IndexPath(row: indexPath.row + i, section: indexPath.section))
                }
                tableView.deleteRows(at: indexPaths, with: .top)
                selectedFolder!.expand = false
            } else {
                selectedFolder!.expand = true
                files.insert(contentsOf: selectedFolder!.visibleFolders, at: indexPath.row + 1)
                for i in 1...selectedFolder!.visibleFolders.count {
                    indexPaths.append(IndexPath(row: indexPath.row + i, section: indexPath.section))
                }
                tableView.insertRows(at: indexPaths, with: .bottom)
            }
            (cell?.accessoryView as? UIImageView)?.tintImage = selectedFolder!.expand ?  #imageLiteral(resourceName: "icon_expand") : #imageLiteral(resourceName: "icon_forward")
        }
    }
    
    func setupBarButton() {
        if selectFolderMode {
            navigationItem.prompt = /"SelectFolderToMove"
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: /"Move", style: .done, target: self, action: #selector(sureMove))
            navigationItem.rightBarButtonItem?.isEnabled = false
        } else if root == File.inbox {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(pickFromFiles))
            if tableView.isEditing {
                navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(multipleSelect))
            }
        } else if root.isExternalFile == false {
            if tableView.isEditing {
                navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(multipleSelect))
                navigationItem.leftBarButtonItem = UIBarButtonItem(title: /"SelectAll", style: .plain, target: self, action: #selector(selectAllFiles))
            } else {
                navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(createFile(_:)))
                if isHomePage {
                    navigationItem.leftBarButtonItem = UIBarButtonItem(image: #imageLiteral(resourceName: "nav_settings"), style: .plain, target: self, action: #selector(showSettings))
                } else {
                    navigationItem.leftBarButtonItem = nil
                }
            }
        }
    }
    
    func doIfPro(_ task: (() -> Void)) {
        if Configure.shared.isPro || passedDate.isFuture {
            task()
            return
        }
        showAlert(title: /"PremiumOnly", message: /"PremiumTips", actionTitles: [/"SubscribeNow",/"Cancel"], textFieldconfigurationHandler: nil) { (index) in
            if index == 0 {
                let sb = UIStoryboard(name: "Settings", bundle: Bundle.main)
                let vc = sb.instantiateVC(PurchaseViewController.self)!
                let nav = NavigationViewController(rootViewController: vc)
                nav.modalPresentationStyle = .formSheet
                self.presentVC(nav)
            }
        }
    }
    
    func setupUI() {
        if selectFolderMode {
            bottomBarOffset.constant = -44 - bottomInset
        } else {
            let barBackground = UIView()
            barBackground.isHidden = true
            barBackground.setBackgroundColor(.navBar)
            navBar?.addSubview(barBackground)
            barBackground.snp.makeConstraints { maker in
                maker.edges.equalToSuperview()
            }
            barBackground.addSubview(searchBar)
            searchBar.showsCancelButton = true
            searchBar.placeholder = /"Search"
            searchBar.delegate = self
            searchBar.snp.makeConstraints { maker in
                maker.top.bottom.equalToSuperview()
                maker.left.equalToSuperview().offset(12)
                maker.right.equalToSuperview().offset(-12)
            }
            
            let line = UIView()
            line.backgroundColor = rgba("262626",0.4)
            view.addSubview(line)
            line.snp.makeConstraints { maker in
                maker.top.left.right.equalTo(self.bottomBar)
                maker.height.equalTo(0.3)
            }
        }

        navBar?.setTintColor(.navTint)
        navBar?.setBackgroundColor(.navBar)
        navBar?.setTitleColor(.navTitle)
        view.setBackgroundColor(.background)
        bottomBar.setBackgroundColor(.background)
        bottomBar.setTintColor(.tint)
        view.setTintColor(.navTint)
        tableView.setBackgroundColor(.tableBackground)
        tableView.setSeparatorColor(.primary)
        emptyView.setBackgroundColor(.background)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "move" {
            if let nav = segue.destination as? UINavigationController,
                let vc = nav.topViewController as? FilesViewController,
                let files = sender as? [File] {
                vc.selectFolderMode = true
                vc.filesToMove = files
                vc.moveFrom = self
            }
            return
        }
        
        if let vc = segue.destination as? FilesViewController,
            let file = sender as? File {
            vc.root = file
            return
        }
        
        if let nav = segue.destination as? UINavigationController,
            let vc = nav.topViewController as? EditViewController,
            let file = sender as? File {
            vc.file = file
            return
        }
    }
}

extension FilesViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        refresh()
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.superview?.isHidden = true
        searchBar.text = ""
        refresh()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

extension FilesViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        tableView.isHidden = files.count == 0 && isHomePage == false
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].count
    }
    
    func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        if !selectFolderMode {
            return 0
        }
        let file = sections[indexPath.section][indexPath.row]
        return file.deep
    }
        
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "item", for: indexPath) as! BaseTableViewCell
        let file = sections[indexPath.section][indexPath.row]
        
        if Configure.shared.showExtensionName == false {
            cell.textLabel?.text = file.displayName
        } else {
            cell.textLabel?.text = file.name
        }
        if file.type == .folder {
            let count = file.children.count
            cell.detailTextLabel?.text = count == 0 ? /"Empty" : "\(file.children.count) " + /"Children"
            if file == File.cloud {
                cell.imageView?.tintImage = #imageLiteral(resourceName: "icon_cloud")
            } else if file == File.inbox {
                cell.imageView?.tintImage = #imageLiteral(resourceName: "icon_box")
                if count == 0 {
                    cell.textLabel?.text = /"ExternalEmpty"
                    cell.detailTextLabel?.text = ""
                }
            } else if file == File.local {
                cell.imageView?.tintImage = #imageLiteral(resourceName: "icon_local")
            } else if file == File.webdav {
                cell.imageView?.tintImage = #imageLiteral(resourceName: "icon_local")
                cell.detailTextLabel?.text = ""
            } else {
                cell.imageView?.tintImage = #imageLiteral(resourceName: "icon_folder")
            }
        } else {
            cell.detailTextLabel?.text = file.modifyDate.readableDate()
            let icon = file.type == .archive ? #imageLiteral(resourceName: "icon_archive") : (file.type == .image ? #imageLiteral(resourceName: "icon_image"): #imageLiteral(resourceName: "icon_text"))
            cell.imageView?.tintImage = icon
        }
        
        cell.needUnlock = isHomePage && indexPath.section == 0 && Configure.shared.isPro == false && passedDate.isPast
                
        if selectFolderMode {
            cell.indentationWidth = 10
            cell.detailTextLabel?.text = nil
        }
        return cell
    }
        
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        impactIfAllow()
        if isHomePage && indexPath.section == 0 {
            tableView.deselectRow(at: indexPath, animated: true)
            if tableView.isEditing {

            } else {
                doIfPro {
                    self.didSelectFile(indexPath)
                }
            }
        } else if tableView.isEditing {
            let file = files[indexPath.row]
            if file.isExternalFile {
                tableView.deselectRow(at: indexPath, animated: true)
            } else {
                selectFiles.append(file)
                let selected = selectFiles.count > 0
                moveButton.isEnabled = selected
                sendButton.isEnabled = selected
                deleteButton.isEnabled = selected
            }
        } else if selectFolderMode {
            didSelectDestFolder(indexPath)
        } else {
            didSelectFile(indexPath)
        }
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            let file = files[indexPath.row]
            selectFiles.removeAll { file == $0 }
            let selected = selectFiles.count > 0
            moveButton.isEnabled = selected
            sendButton.isEnabled = selected
            deleteButton.isEnabled = selected
        }
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if selectFolderMode {
            return false
        }
        if isHomePage && indexPath.section == 0 {
            let file = self.sections[indexPath.section][indexPath.row]
            return file.isExternalFile
        }
        return self.root.isExternalFile == false
    }
    
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
        
        let file = self.sections[indexPath.section][indexPath.row]
        if file.isExternalFile {
            return .delete
        }
        return UITableViewCellEditingStyle(rawValue: UITableViewCellEditingStyle.delete.rawValue | UITableViewCellEditingStyle.insert.rawValue)!
    }
    
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        let file = self.sections[indexPath.section][indexPath.row]
        
        if file.isExternalFile {
            let deleteAction = UITableViewRowAction(style: .destructive, title: /"Delete") { [unowned self](_, indexPath) in
                impactIfAllow()
                if file == File.current {
                    file.close()
                    self.editFile(nil)
                }
                file.trash()
                if self.isHomePage {
                    self.items.remove(at: indexPath.row)
                } else {
                    self.files.remove(at: indexPath.row)
                }
                tableView.deleteRows(at: [indexPath], with: .middle)
            }
            return [deleteAction]
        }
        
        let deleteAction = UITableViewRowAction(style: .destructive, title: /"Delete") { [unowned self](_, indexPath) in
            impactIfAllow()
            self.showDestructiveAlert(title: nil, message: /"DeleteMessage", actionTitle: /"Delete") {
                file.trash()
                if file == File.current  {
                    file.close()
                    self.editFile(nil)
                }
                self.files.remove(at: indexPath.row)
                tableView.deleteRows(at: [indexPath], with: .middle)
            }
        }
        
        let renameAction = UITableViewRowAction(style: .default, title: /"Rename") { [unowned self](_, indexPath) in
            impactIfAllow()
            if file.disable {
                ActivityIndicator.showError(withStatus: /"CanNotAccesseThisFile")
                return
            }
            self.showAlert(title: nil, message: /"RenameTips", actionTitles: [/"Cancel",/"OK"], textFieldconfigurationHandler: { (textField) in
                textField.text = file.displayName
                textField.clearButtonMode = .whileEditing
                textField.placeholder = /"FileNamePlaceHolder"
                self.textField = textField
            }, actionHandler: { (index) in
                let name = (self.textField?.text ?? "").trimmed()
                if index == 0 || name.count == 0 || name == file.displayName {
                    return
                }
                if name.isValidFileName {
                    if file == File.current {
                        ActivityIndicator.show()
                        file.close { success in
                            ActivityIndicator.dismiss()
                            if success && file.rename(to: name) {
                                tableView.reloadRows(at: [indexPath], with: .automatic)
                                if isPad {
                                     self.openFile(file)
                                }
                            } else {
                                ActivityIndicator.showError(withStatus: /"CanNotOperateThisFile")
                            }
                        }
                    } else {
                        if file.rename(to: name) {
                            tableView.reloadRows(at: [indexPath], with: .automatic)
                        } else {
                            ActivityIndicator.showError(withStatus: /"CanNotOperateThisFile")
                        }
                    }
                } else {
                    ActivityIndicator.showError(withStatus: /"FileNameError")
                }
            })
        }
        
        let moveAction = UITableViewRowAction(style: .default, title: /"Move") { [unowned self](_, indexPath) in
            impactIfAllow()
            self.performSegue(withIdentifier: "move", sender: [file])
        }
        
        renameAction.backgroundColor = .lightGray
        moveAction.backgroundColor = .orange
        return [deleteAction,renameAction,moveAction]
    }
}

extension FilesViewController: UIDocumentPickerDelegate {
    
    @objc func pickFromFiles() {
        let picker = UIDocumentPickerViewController(documentTypes: ["public.text"], in: .open)
        picker.delegate = self
        picker.modalPresentationStyle = .formSheet
        presentVC(picker)
    }

    func accessFile(_ url: URL) {
        if let file = File.local.findChild(url.path) ?? File.cloud.findChild(url.path) {
            openFile(file)
            return
        }
        ActivityIndicator.show()
        let accessed = url.startAccessingSecurityScopedResource()
        if !accessed {
            ActivityIndicator.dismiss()
            ActivityIndicator.showError(withStatus: /"CanNotAccesseThisFile")
            return
        }
        var error: NSError? = nil
        NSFileCoordinator().coordinate(readingItemAt: url, options: .forUploading, error: &error) { newURL in
            print(newURL)
            guard let values = try? url.resourceValues(forKeys: [URLResourceKey.isDirectoryKey]) else {
                url.stopAccessingSecurityScopedResource()
                ActivityIndicator.dismiss()
                ActivityIndicator.showError(withStatus: /"CanNotAccesseThisFile")
                return
            }
            if values.isDirectory ?? false {
                didPickFolder(url)
            } else {
                didPickFile(url)
            }
        }
    }
    
    func didPickFile(_ url: URL) {
        showActionSheet(actionTitles: [/"ImportFile",/"OpenInPlace"]) { index in
            let name = url.deletingPathExtension().lastPathComponent
            if index == 0 {
                guard let data = try? Data(contentsOf: url) else {
                    ActivityIndicator.showError(withStatus: /"CanNotAccesseThisFile")
                    return
                }
                url.stopAccessingSecurityScopedResource()
                if let newFile = File.local.createFile(name: name, contents: data, type: .text) {
                    self.openFile(newFile)
                }
            } else {
                guard let data = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) else {
                    ActivityIndicator.showError(withStatus: /"CanNotAccesseThisFile")
                    return
                }
                url.stopAccessingSecurityScopedResource()
                if let newFile = File.inbox.createFile(name: name, contents: data, type: .text) {
                    self.openFile(newFile)
                }
            }
        }
        ActivityIndicator.dismiss()
    }
    
    func didPickFolder(_ url: URL) {
        ActivityIndicator.dismiss()
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        accessFile(url)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if urls.count > 0 {
            accessFile(urls.first!)
        }
    }
}

extension FilesViewController: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        if let url = previewingFile?.url as NSURL? { return url }
        return NSURL()
    }
    
}

