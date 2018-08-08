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
import PlayKit

let setSmallerOfflineDRMExpirationMinutes: Int? = 5
//let setSmallerOfflineDRMExpirationMinutes: Int? = nil

class Item {
    let id: String
    let title: String
    let partnerId: Int?
    
    var url: URL?
    var entry: PKMediaEntry?

    init(id: String, url: String) {
        self.id = id
        self.title = id
        self.url = URL(string: url)!
        
        let source = PKMediaSource.init(id, contentUrl: URL(string: url))
        self.entry = PKMediaEntry(id, sources: [source])
        
        self.partnerId = nil
    }
    
    init(_ title: String, id: String, partnerId: Int, env: String = "http://cdnapi.kaltura.com") {
        self.id = id
        self.title = title
        self.partnerId = partnerId
        
        self.url = nil
        
        OVPMediaProvider(SimpleOVPSessionProvider(serverURL: env, partnerId: Int64(partnerId), ks: nil))
            .set(entryId: id)
            .loadMedia { (entry, error) in
                
                if let minutes = setSmallerOfflineDRMExpirationMinutes {
                    entry?.sources?.forEach({ (source) in
                        if let drmData = source.drmData, let fpsData = drmData.first as? FairPlayDRMParams {
                            var lic = fpsData.licenseUri!.absoluteString
                            lic.append(contentsOf: "&rental_duration=\(minutes*60)")
                            fpsData.licenseUri = URL(string: lic)
                        }
                    })
                }
                
                self.entry = entry
        }
    }
}

class ViewController: UIViewController {
    let dummyFileName = "dummyfile"
    let videoViewControllerSegueIdentifier = "videoViewController"
    
    let cm = ContentManager.shared
    let lam = LocalAssetsManager.managerWithDefaultDataStore()
    
    let items = [
        Item("FPS: Ella 1", id: "1_x14v3p06", partnerId: 1788671),
        Item("FPS: QA 1", id: "0_4s6xvtx3", partnerId: 4171, env: "http://qa-apache-php7.dev.kaltura.com"),
        Item("FPS: QA 2", id: "0_7o8zceol", partnerId: 4171, env: "http://qa-apache-php7.dev.kaltura.com"),
        Item("Clear: Kaltura", id: "1_sf5ovm7u", partnerId: 243342),
        Item(id: "QA multi/multi", url: "http://qa-apache-testing-ubu-01.dev.kaltura.com/p/1091/sp/109100/playManifest/entryId/0_mskmqcit/flavorIds/0_et3i1dux,0_pa4k1rn9/format/applehttp/protocol/http/a.m3u8"),
        Item(id: "Eran multi audio", url: "https://cdnapisec.kaltura.com/p/2035982/sp/203598200/playManifest/entryId/0_7s8q41df/format/applehttp/protocol/https/name/a.m3u8?deliveryProfileId=4712"),
        Item(id: "Trailer", url: "http://cdnbakmi.kaltura.com/p/1758922/sp/175892200/playManifest/entryId/0_ksthpwh8/format/applehttp/tags/ipad/protocol/http/f/a.m3u8"),
        Item(id: "AES-128 multi-key", url: "https://noamtamim.com/random/hls/test-enc-aes/multi.m3u8"),
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
                    if item?.state == .completed {
                        self.progressView.progress = 1.0
                    } else if let downloadedSize = item?.downloadedSize, let estimatedSize = item?.estimatedSize, estimatedSize > 0 {
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
        
        cm.setDefaultAudioBitrateEstimation(bitrate: 128000)

        // initialize UI
        selectedItem = items.first!
        itemPickerView.delegate = self
        itemPickerView.dataSource = self
        itemTextField.inputView = itemPickerView
        itemTextField.inputView?.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        itemTextField.text = items.first?.title ?? ""
        itemTextField.inputAccessoryView = getAccessoryView()
        
        languageCodePickerView.delegate = self
        languageCodePickerView.dataSource = self
        languageCodeTextField.inputView = languageCodePickerView
        languageCodeTextField.inputView?.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        languageCodeTextField.inputAccessoryView = getAccessoryView()
        
        // setup content manager
        cm.delegate = self
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func addItem(_ sender: UIButton) {
        
        guard let entry = self.selectedItem.entry else {
            toastMedium("No entry")
            return
        }
        
        guard let mediaSource = lam.getPreferredDownloadableMediaSource(for: entry) else {
            toastMedium("No media source")
            return
        }
        
        print("Selected to download: \(String(describing: mediaSource.contentUrl))")
        
        var item: DTGItem?
        do {
            item = try cm.itemById(entry.id)
            if item == nil {
                item = try cm.addItem(id: entry.id, url: mediaSource.contentUrl!)
            }
        } catch {
            toastMedium("Can't add item: " + error.localizedDescription)
            return
        }

        guard let dtgItem = item else {
            toastMedium("Can't add item")
            return
        }
        
        self.statusLabel.text = dtgItem.state.asString()
        
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
        } catch {
            toastLong(error.localizedDescription)
        }
    }
    
    @IBAction func pause(_ sender: UIButton) {
        do {
            try cm.pauseItem(id: self.selectedItem.id)
        } catch {
            toastLong(error.localizedDescription)
        }
    }
    
    @IBAction func remove(_ sender: UIButton) {
        let id = self.selectedItem.id
        do {
            guard let url = try self.cm.itemPlaybackUrl(id: id) else {
                toastMedium("Can't get local url")
                return
            }
            
            lam.unregisterDownloadedAsset(location: url, callback: { (error) in
                DispatchQueue.main.async {
                    self.toastMedium("Unregister complete")
                }
            })
            
            try? cm.removeItem(id: id)
            
        } catch {
            toastLong(error.localizedDescription)
        }
    }
    
    @IBAction func renew(_ sender: UIButton) {
        let id = self.selectedItem.id
        do {
            guard let url = try self.cm.itemPlaybackUrl(id: id) else {
                toastMedium("Can't get local url")
                return
            }
            
            guard let entry = self.selectedItem.entry, 
                let source = lam.getPreferredDownloadableMediaSource(for: entry) else {
                    
                    toastMedium("No valid source")
                    return
            }
                        
            lam.renewDownloadedAsset(location: url, mediaSource: source) { (error) in
                DispatchQueue.main.async {
                    self.toastMedium("Renew complete")
                }
            }
            
        } catch {
            toastLong(error.localizedDescription)
        }
    }

    @IBAction func checkStatus(_ sender: UIButton) {
        let id = self.selectedItem.id
        do {
            guard let url = try self.cm.itemPlaybackUrl(id: id) else {
                toastMedium("Can't get local url")
                return
            }
            
            guard let exp = lam.getLicenseExpirationInfo(location: url) else {
                toastMedium("Unknown")
                return
            }
            
            let expString = DateFormatter.localizedString(from: exp.expirationDate, dateStyle: .long, timeStyle: .long)
            
            if exp.expirationDate < Date() {
                toastLong("EXPIRED at \(expString)")
            } else {
                toastLong("VALID until \(expString)")
            }
            
        } catch {
            toastLong(error.localizedDescription)
        }
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
                        DispatchQueue.main.async {
                            self.toastMedium("Finished Filling Device with Dummy Data")
                        }
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
                        DispatchQueue.main.async {
                            self.toastMedium("Finished Updating Device Dummy Data File")
                        }
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
    
    @objc func doneButtonTapped(button: UIBarButtonItem) -> Void {
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
        self.view.makeToast(message, duration: 4, position: .center)
    }
}

/************************************************************/
// MARK: - Navigation
/************************************************************/

extension ViewController {
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        do {
            if identifier == self.videoViewControllerSegueIdentifier {
                guard let item = try cm.itemById(self.selectedItem.id) else {
                    toastMedium("cannot segue to video view controller until download is finished")
                    return false
                }
                if item.state == .completed {
                    return true
                }
                toastMedium("cannot segue to video view controller until download is finished")
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
                    self.view.layoutIfNeeded()
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
            return items[row].title
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
            self.itemTextField.text = items[row].title
            self.selectedItem = items[row]
        }
    }
}
