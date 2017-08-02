//
//  TextViewController.swift
//  MarkLite
//
//  Created by zhubch on 2017/6/28.
//  Copyright © 2017年 zhubch. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import EZSwiftExtensions

class TextViewController: UIViewController {

    @IBOutlet weak var editView: UITextView!
    @IBOutlet weak var placeholderLabel: UILabel!
    @IBOutlet weak var countLabel: UILabel!
    @IBOutlet weak var bottomSpace: NSLayoutConstraint!
    
    @IBOutlet weak var undoButton: UIButton!
    @IBOutlet weak var redoButton: UIButton!

    var previewHandler: (()->Void)?

    let disposeBag = DisposeBag()
    let manager = MarkdownHighlightManager()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        editView.backgroundColor = .white
        editView.inputAccessoryView = AssistBar()
        let assistBar = AssistBar()
        assistBar.textView = editView
        assistBar.viewController = self
        
        Configure.shared.currentFile.asObservable().subscribe(onNext: { [unowned self] (file) in
            guard let file = file else { return }

            self.editView.attributedText = self.manager.highlight(file.text.value)
            self.editView.rx.text.map{ $0 ?? "" }.bind(to: file.text).addDisposableTo(self.disposeBag)
            self.editView.attributedText = self.manager.highlight(file.text.value)
        }).addDisposableTo(disposeBag)
        
        editView.rx.didChange.subscribe { [unowned self] _ in
            self.highlight()
        }.addDisposableTo(disposeBag)
        
        editView.rx.text.map{($0?.length ?? 0) > 0}.bind(to: placeholderLabel.rx.isHidden).addDisposableTo(disposeBag)
        
        addNotificationObserver(Notification.Name.UIKeyboardWillChangeFrame.rawValue, selector: #selector(keyboardWillChange(_:)))
    }
    
    func highlight() {
        if editView.markedTextRange != nil {
            return
        }
        editView.isScrollEnabled = false
        let selectedRange = editView.selectedRange
        editView.attributedText = manager.highlight(editView.text)
        editView.selectedRange = selectedRange;
        editView.isScrollEnabled = true
    }
    
    @IBAction func preview(_ sender:UIButton) {
        editView.resignFirstResponder()
        previewHandler?()
    }
    
    @IBAction func chooseTag(_ sender: UIButton) {
        let items = Configure.shared.root.children.map{$0.name}
        let pos = CGPoint(x: sender.x, y: windowHeight - CGFloat(50) - CGFloat(items.count * 40))
        MenuView(items: items, postion: pos) { (index) in
            //
            }.show()
    }
    
    @IBAction func undo(_ sender: UIButton) {
        editView.undoManager?.undo()
        
        self.redoButton.isEnabled = self.editView.undoManager?.canRedo ?? false
        self.undoButton.isEnabled = self.editView.undoManager?.canUndo ?? false
    }
    
    @IBAction func redo(_ sender: UIButton) {
        editView.undoManager?.redo()
        self.redoButton.isEnabled = self.editView.undoManager?.canRedo ?? false
        self.undoButton.isEnabled = self.editView.undoManager?.canUndo ?? false
    }
    
    func keyboardWillChange(_ noti: NSNotification) {
        guard let frame = (noti.userInfo?[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        bottomSpace.constant = self.view.h - frame.y
        editView.scrollRangeToVisible(editView.selectedRange)
        UIView.animate(withDuration: 1) {
            self.view.layoutIfNeeded()
        }
    }
    
    deinit {
        print("deinit text_vc")
    }
    
}