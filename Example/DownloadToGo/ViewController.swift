//
//  ViewController.swift
//  DownloadToGo
//
//  Created by noamtamim on 07/07/2017.
//  Copyright (c) 2017 noamtamim. All rights reserved.
//

import UIKit
import DownloadToGo

class ViewController: UIViewController {
    
    typealias Item = (id: String, url: URL)
    
    let cm = DTGSharedContentManager
    
    // FIXME: change the urls for the correct default ones
    let items = [
        Item(id: "hls-clear", url: URL(string: "https://cdnapisec.kaltura.com/p/2035982/sp/203598200/playManifest/entryId/0_7s8q41df/format/applehttp/protocol/https/name/a.m3u8?deliveryProfileId=4712")!),
        Item(id: "hls-multi-audio", URL(string: "https://cdnapisec.kaltura.com/p/2035982/sp/203598200/playManifest/entryId/0_7s8q41df/format/applehttp/protocol/https/name/a.m3u8?deliveryProfileId=4712")!),
        Item(id: "hls-multi-video", url: URL(string: "https://cdnapisec.kaltura.com/p/2035982/sp/203598200/playManifest/entryId/0_7s8q41df/format/applehttp/protocol/https/name/a.m3u8?deliveryProfileId=4712")!),
        Item(id: "hls-multi", url: URL(string: "https://cdnapisec.kaltura.com/p/2035982/sp/203598200/playManifest/entryId/0_7s8q41df/format/applehttp/protocol/https/name/a.m3u8?deliveryProfileId=4712")!)
    ]
    
    let itemPickerView: UIPickerView = {
        let picker = UIPickerView()
        return picker
    }()
    
    var selectedItem: Item!
    
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var itemTextField: UITextField!
    @IBOutlet weak var progressView: UIProgressView!

    override func viewDidLoad() {
        super.viewDidLoad()
        // initialize UI
        self.selectedItem = self.items.first!
        itemPickerView.delegate = self
        itemPickerView.dataSource = self
        itemTextField.inputView = itemPickerView
        itemTextField.text = items.first?.id ?? ""
        self.itemTextField.inputAccessoryView = getAccessoryView()
        
        // setup content manager
        cm.itemDelegate = self
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func addItem(_ sender: UIButton) {
        _ = cm.addItem(id: self.selectedItem.id, url: self.selectedItem.url)
        self.statusLabel.text = cm.itemById(selectedItem.id)?.state.asString()
    }
    
    @IBAction func loadMetadata(_ sender: UIButton) {
        cm.loadItemMetadata(id: self.selectedItem.id, preferredVideoBitrate: 300000) { (item, videoTrack, error) in
            print(item, videoTrack)
        }
    }
    
    @IBAction func start(_ sender: UIButton) {
        do {
            try cm.startItem(id: self.selectedItem.id)
        } catch let e {
            print("error: \(e.localizedDescription)")
        }
    }
    
    @IBAction func pause(_ sender: UIButton) {
        cm.pauseItem(id: self.selectedItem.id)
    }
    
    @IBAction func playDownloadedItem(_ sender: UIButton) {
        
    }
    
    @IBAction func remove(_ sender: UIButton) {
        
    }
    
    func getAccessoryView() -> UIView {
        let toolBar = UIToolbar(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: 44))
        let doneButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(self.doneButtonTapped(button:)))
        toolBar.items = [doneButton]
        
        return toolBar
    }
    
    func doneButtonTapped(button: UIBarButtonItem) -> Void {
        let item = cm.itemById(self.selectedItem.id)
        self.statusLabel.text = item?.state.asString()
        self.itemTextField.resignFirstResponder()
    }
}

/************************************************************/
// MARK: - DTGItemDelegate
/************************************************************/

extension ViewController: DTGItemDelegate {
    
    func item(id: String, didFailWithError error: Error) {
        print("item: \(id) failed with error: \(error)")
        self.statusLabel.text = DTGItemState.failed.asString()
    }
    
    func item(id: String, didDownloadData totalBytesDownloaded: Int64, totalBytesEstimated: Int64) {
        if id == self.selectedItem.id && totalBytesEstimated > totalBytesDownloaded { // update the progress for selected id only
            self.progressView.progress = Float(totalBytesDownloaded / totalBytesEstimated)
        } else {
            print("error: totalBytesEstimated is lower than totalBytesDownloaded or 0")
        }
    }
    
    func item(id: String, didChangeToState newState: DTGItemState) {
        DispatchQueue.main.async {
            if newState == .completed && id == self.selectedItem.id {
                self.progressView.progress = 1.0
            }
            self.statusLabel.text = newState.asString()
        }
    }
}

/************************************************************/
// MARK: - UIPickerViewDataSource
/************************************************************/

extension ViewController: UIPickerViewDataSource {
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return self.items.count
    }
}

/************************************************************/
// MARK: - UIPickerViewDelegate
/************************************************************/

extension ViewController: UIPickerViewDelegate {
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return items[row].id
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        self.itemTextField.text = items[row].id
        self.selectedItem = items[row]
    }
}


