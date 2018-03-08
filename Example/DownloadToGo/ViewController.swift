//
//  ViewController.swift
//  DownloadToGo
//
//  Created by noamtamim on 07/07/2017.
//  Copyright (c) 2017 noamtamim. All rights reserved.
//

import UIKit
import DownloadToGo
import Toast_Swift

class Item {
    let id: String
    let url: URL
    
    init(id: String, url: String) {
        self.id = id
        self.url = URL(string: url)!
    }
}

class ViewController: UIViewController {
    let dummyFileName = "dummyfile"
    let videoViewControllerSegueIdentifier = "videoViewController"
    
    let cm = ContentManager.shared
    
    // FIXME: change the urls for the correct default ones
    let items = [
        Item(id: "QA multi/multi", url: "http://qa-apache-testing-ubu-01.dev.kaltura.com/p/1091/sp/109100/playManifest/entryId/0_mskmqcit/flavorIds/0_et3i1dux,0_pa4k1rn9/format/applehttp/protocol/http/a.m3u8"),
        Item(id: "Eran multi audio", url: "https://cdnapisec.kaltura.com/p/2035982/sp/203598200/playManifest/entryId/0_7s8q41df/format/applehttp/protocol/https/name/a.m3u8?deliveryProfileId=4712"),
        Item(id: "Kaltura 1", url: "http://cdnapi.kaltura.com/p/243342/sp/24334200/playManifest/entryId/1_sf5ovm7u/flavorIds/1_d2uwy7vv,1_jl7y56al/format/applehttp/protocol/http/a.m3u8"),
        Item(id: "Kaltura multi captions", url: "https://cdnapisec.kaltura.com/p/811441/sp/81144100/playManifest/entryId/1_mhyj12pj/format/applehttp/protocol/https/a.m3u8"),
        Item(id: "Trailer", url: "http://cdnbakmi.kaltura.com/p/1758922/sp/175892200/playManifest/entryId/0_ksthpwh8/format/applehttp/tags/ipad/protocol/http/f/a.m3u8"),
        Item(id: "AES-128 multi-key", url: "https://noamtamim.com/random/hls/test-enc-aes/multi.m3u8"),
        Item(id: "Empty", url: "https://cdnapisec.kaltura.com/p/2215841/playManifest/entryId/1_58e88ugs/format/applehttp/protocol/https/a.m3u8"),
    ]
    
    let itemPickerView: UIPickerView = {
        let picker = UIPickerView()
        return picker
    }()
    
    let languageCodePickerView: UIPickerView = {
        let picker = UIPickerView()
        return picker
    }()
    
    var selectedItem: Item! {
        didSet {
            do {
                let item = try cm.itemById(selectedItem.id)
                DispatchQueue.main.async {
                    self.statusLabel.text = item?.state.asString() ?? ""
                    if let downloadedSize = item?.downloadedSize, let estimatedSize = item?.estimatedSize, estimatedSize > 0 {
                        self.progressView.progress = Float(downloadedSize) / Float(estimatedSize)
                    } else {
                        self.progressView.progress = 0.0
                    }
                }
            } catch {
                // handle error here
                print("error: \(error.localizedDescription)")
            }
        }
    }
    
    var selectedTextLanguageCode: String?
    var selectedAudioLanguageCode: String?
    
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var itemTextField: UITextField!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var languageCodeTextField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // initialize UI
        self.selectedItem = self.items.first!
        itemPickerView.delegate = self
        itemPickerView.dataSource = self
        itemTextField.inputView = itemPickerView
        itemTextField.text = items.first?.id ?? ""
        self.itemTextField.inputAccessoryView = getAccessoryView()
        
        self.languageCodePickerView.delegate = self
        self.languageCodePickerView.dataSource = self
        self.languageCodeTextField.inputView = self.languageCodePickerView
        self.languageCodeTextField.inputAccessoryView = getAccessoryView()
        
        // setup content manager
        cm.delegate = self
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func addItem(_ sender: UIButton) {
        do {
            _ = try cm.addItem(id: self.selectedItem.id, url: self.selectedItem.url)
            self.statusLabel.text = try cm.itemById(selectedItem.id)?.state.asString()
        } catch {
            // handle db issues here...
            print(error.localizedDescription)
        }
    }
    
    @IBAction func loadMetadata(_ sender: UIButton) {
        DispatchQueue.global().async {
            do {
                try self.cm.loadItemMetadata(id: self.selectedItem.id, preferredVideoBitrate: 300000)
                print("Item Metadata Loaded")
            } catch {
                DispatchQueue.main.async {
                    self.toastMedium("loadItemMetadata failed \(error)")
                }
            }
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
        do {
            try cm.pauseItem(id: self.selectedItem.id)
        } catch let e {
            print("error: \(e.localizedDescription)")
        }
    }
    
    @IBAction func remove(_ sender: UIButton) {
        let id = selectedItem.id
        try? cm.removeItem(id: id)
    }
    
    @IBAction func actionBarButtonTouched(_ sender: UIBarButtonItem) {
        let actionAlertController = UIAlertController(title: "Perform Action", message: "Please select an action to perform", preferredStyle: .actionSheet)
        // fille device with dummy file action
        actionAlertController.addAction(UIAlertAction(title: "Fill device disk using dummy file", style: .default, handler: { (action) in
            let dialog = UIAlertController(title: "Fill Disk", message: "Please put the amount of MB to fill disk", preferredStyle: .alert)
            dialog.addTextField(configurationHandler: { (textField) in
                textField.placeholder = "Size in MB"
                textField.keyboardType = .numberPad
            })
            dialog.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) in
                guard let text = dialog.textFields?.first?.text, let sizeInMb = Int(text) else { return }
                let fileManager = FileManager.default
                if let dir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
                    let fileUrl = dir.appendingPathComponent(self.dummyFileName, isDirectory: false).appendingPathExtension("txt")
                    if !fileManager.fileExists(atPath: fileUrl.path) {
                        fileManager.createFile(atPath: fileUrl.path, contents: Data(), attributes: nil)
                    }
                    do {
                        let fileHandle = try FileHandle(forUpdating: fileUrl)
                        autoreleasepool {
                            for _ in 1...sizeInMb {
                                fileHandle.write(Data.init(count: 1000000))
                            }
                        }
                        fileHandle.closeFile()
                        self.toastMedium("Finished Filling Device with Dummy Data")
                    } catch {
                        print("error: \(error)")
                    }
                }
            }))
            dialog.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            self.present(dialog, animated: true, completion: nil)
        }))
        // update dummy file size action
        actionAlertController.addAction(UIAlertAction(title: "Update dummy file size", style: .default, handler: { (action) in
            let dialog = UIAlertController(title: "Update Dummy file Size", message: "Please put the amount of MB to reduce from dummy file", preferredStyle: .alert)
            dialog.addTextField(configurationHandler: { (textField) in
                textField.placeholder = "Size in MB"
                textField.keyboardType = .numberPad
            })
            dialog.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) in
                guard let text = dialog.textFields?.first?.text, let sizeInMb = Int(text) else { return }
                let fileManager = FileManager.default
                if let dir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
                    let fileUrl = dir.appendingPathComponent(self.dummyFileName, isDirectory: false).appendingPathExtension("txt")
                    guard fileManager.fileExists(atPath: fileUrl.path) else { return } // make sure file exits
                    do {
                        let fileHandle = try FileHandle(forUpdating: fileUrl)
                        fileHandle.truncateFile(atOffset: fileHandle.seekToEndOfFile() - UInt64(sizeInMb * 1000000))
                        fileHandle.closeFile()
                        self.toastMedium("Finished Updating Device Dummy Data File")
                    } catch {
                        print("error: \(error)")
                    }
                }
            }))
            dialog.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            self.present(dialog, animated: true, completion: nil)
        }))
        // remove dummy file action
        actionAlertController.addAction(UIAlertAction(title: "Remove dummy file", style: .default, handler: { (action) in
            let fileManager = FileManager.default
            if let dir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
                let fileUrl = dir.appendingPathComponent(self.dummyFileName, isDirectory: false).appendingPathExtension("txt")
                do {
                    try fileManager.removeItem(at: fileUrl)
                } catch {
                    print("error: \(error)")
                }
            }
        }))
        self.present(actionAlertController, animated: true, completion: nil)
    }
    
    func getAccessoryView() -> UIView {
        let toolBar = UIToolbar(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: 44))
        let doneButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(self.doneButtonTapped(button:)))
        toolBar.items = [doneButton]
        
        return toolBar
    }
    
    func doneButtonTapped(button: UIBarButtonItem) -> Void {
        do {
            let item = try cm.itemById(self.selectedItem.id)
            self.statusLabel.text = item?.state.asString()
            self.itemTextField.resignFirstResponder()
            self.languageCodeTextField.resignFirstResponder()
        } catch {
            // handle db issues here...
            print("error: \(error.localizedDescription)")
        }
    }
    
    func toastShort(_ message: String) {
        print(message)
        self.view.makeToast(message, duration: 0.6, position: .center)
    }
    
    func toastMedium(_ message: String) {
        print(message)
        self.view.makeToast(message, duration: 1.0, position: .center)
    }
    
    func toastLong(_ message: String) {
        print(message)
        self.view.makeToast(message, duration: 1.5, position: .center)
    }
}

/************************************************************/
// MARK: - Navigation
/************************************************************/

extension ViewController {
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        do {
            if identifier == self.videoViewControllerSegueIdentifier {
                guard let item = try cm.itemById(selectedItem.id) else {
                    print("cannot segue to video view controller until download is finished")
                    return false
                }
                if item.state == .completed {
                    return true
                }
                print("cannot segue to video view controller until download is finished")
                return false
            }
        } catch {
            // handle db issues here...
            print("error: \(error.localizedDescription)")
        }
        return true
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == self.videoViewControllerSegueIdentifier {
            let destinationVC = segue.destination as! VideoViewController
            do {
                destinationVC.contentUrl = try self.cm.itemPlaybackUrl(id: self.selectedItem.id)
                destinationVC.textLanguageCode = self.selectedTextLanguageCode
                destinationVC.audioLanguageCode = self.selectedAudioLanguageCode
            } catch {
                print("error: \(error.localizedDescription)")
            }
        }
    }
}

/************************************************************/
// MARK: - ContentManagerDelegate
/************************************************************/

extension ViewController: ContentManagerDelegate {
    
    func item(id: String, didDownloadData totalBytesDownloaded: Int64, totalBytesEstimated: Int64?) {
        if let totalBytesEstimated = totalBytesEstimated, id == self.selectedItem.id {
            if totalBytesEstimated > totalBytesDownloaded {
                DispatchQueue.main.async {
                    self.progressView.progress = Float(totalBytesDownloaded) / Float(totalBytesEstimated)
                }
            } else if totalBytesDownloaded >= totalBytesEstimated && totalBytesEstimated > 0 {
                DispatchQueue.main.async {
                    self.progressView.progress = 1.0
                }
            } else {
                print("issue with calculating progress, estimated: \(totalBytesEstimated), downloaded: \(totalBytesDownloaded)")
            }
        } else {
            print("issue with calculating progress, no estimated size.")
        }
    }
    
    func item(id: String, didChangeToState newState: DTGItemState, error: Error?) {
        DispatchQueue.main.async {
            if newState == .completed && id == self.selectedItem.id {
                self.progressView.progress = 1.0
            } else if newState == .removed && id == self.selectedItem.id {
                self.progressView.progress = 0.0
            } else if newState == .failed {
                print("error: \(String(describing: error?.localizedDescription))")
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
        if pickerView === self.languageCodePickerView {
            return 2
        } else {
            return 1
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        if pickerView === self.languageCodePickerView {
            do {
                guard let item = try self.cm.itemById(self.selectedItem.id) else { return 0 }
                if component == 0 {
                    return item.selectedTextTracks.count
                } else {
                    return item.selectedAudioTracks.count
                }
            } catch {
                return 0
            }
        } else {
            return self.items.count
        }
    }
}

/************************************************************/
// MARK: - UIPickerViewDelegate
/************************************************************/

extension ViewController: UIPickerViewDelegate {
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if pickerView === self.languageCodePickerView {
            do {
                guard let item = try self.cm.itemById(self.selectedItem.id) else { return "" }
                if component == 0 {
                    return item.selectedTextTracks[row].title
                } else {
                    return item.selectedAudioTracks[row].title
                }
            } catch {
                return ""
            }
        } else {
            return items[row].id
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if pickerView === self.languageCodePickerView {
            do {
                guard let item = try self.cm.itemById(self.selectedItem.id) else { return }
                if component == 0 {
                    guard item.selectedTextTracks.count > 0 else { return }
                    self.selectedTextLanguageCode = item.selectedTextTracks[row].languageCode
                } else {
                    guard item.selectedAudioTracks.count > 0 else { return }
                    self.selectedAudioLanguageCode = item.selectedAudioTracks[row].languageCode
                }
                self.languageCodeTextField.text = "text code: \(self.selectedTextLanguageCode ?? ""), audio code: \(self.selectedAudioLanguageCode ?? "")"
            } catch {
                
            }
        } else {
            self.itemTextField.text = items[row].id
            self.selectedItem = items[row]
        }
    }
}
