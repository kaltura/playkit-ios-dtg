//
//  ViewController.swift
//  DownloadToGo
//
//  Created by noamtamim on 07/07/2017.
//  Copyright (c) 2017 noamtamim. All rights reserved.
//

import UIKit
import DownloadToGo
import Toast
import PlayKit
import PlayKitProviders

let setSmallerOfflineDRMExpirationMinutes: Int? = 5
//let setSmallerOfflineDRMExpirationMinutes: Int? = nil

let defaultAudioBitrateEstimation: Int = 64000


struct ItemJSON: Codable {
    let id: String
    let title: String?
    let partnerId: Int?
    let ks: String?
    let env: String?

    let url: String?
    
    let options: OptionsJSON?
    
    func toItem() -> Item {
        let item: Item
        let title = self.title ?? self.id
        if let partnerId = self.partnerId {
            item = Item(title, id: self.id, partnerId: partnerId, ks: self.ks, env: self.env)
        } else if let url = self.url {
            item = Item(title, id: self.id, url: url)
        } else {
            fatalError("Invalid item, missing `partnerId` and `url`")
        }
        item.options = options?.toOptions()
        
        return item
    }
}

struct OptionsJSON: Codable {
    let audioLangs: [String]?
    let allAudioLangs: Bool?
    let textLangs: [String]?
    let allTextLangs: Bool?
    let videoCodecs: [String]?
    let audioCodecs: [String]?
    let videoWidth: Int?
    let videoHeight: Int?
    let videoBitrates: [String:Int]?
    let allowInefficientCodecs: Bool?
    
    func toOptions() -> DTGSelectionOptions {
        let opts = DTGSelectionOptions()
        
        opts.allAudioLanguages = allAudioLangs ?? false
        opts.audioLanguages = audioLangs
        
        opts.allTextLanguages = allTextLangs ?? false
        opts.textLanguages = textLangs
        
        opts.allowInefficientCodecs = allowInefficientCodecs ?? false
        
        if let codecs = audioCodecs {
            opts.audioCodecs = codecs.compactMap({ (tag) -> DTGSelectionOptions.AudioCodec? in
                switch tag {
                case "mp4a": return .mp4a
                case "ac3": return .ac3
                case "eac3", "ec3": return .eac3
                default: return nil
                }
            })
        }

        if let codecs = videoCodecs {
            opts.videoCodecs = codecs.compactMap({ (tag) -> DTGSelectionOptions.VideoCodec? in
                switch tag {
                case "avc1": return .avc1
                case "hevc", "hvc1": return .hevc
                default: return nil
                }
            })
        }

        opts.videoWidth = videoWidth
        opts.videoHeight = videoHeight
        
        if let bitrates = videoBitrates {
            opts.videoBitrates = bitrates.compactMap { (k ,v) -> DTGSelectionOptions.VideoBitrate? in
                switch k {
                case "avc1": return .avc1(v)
                case "hevc", "hvc1": return .hevc(v)
                default: return nil
                }
            }
        }
        
        return opts
    }
}

class Item {
    static let defaultEnv = "http://cdnapi.kaltura.com"
    let id: String
    let title: String
    let partnerId: Int?
    
    var url: URL?
    var entry: PKMediaEntry?
    
    var options: DTGSelectionOptions?

    init(_ title: String, id: String, url: String) {
        self.id = id
        self.title = title
        self.url = URL(string: url)!
        
        let source = PKMediaSource(id, contentUrl: URL(string: url))
        self.entry = PKMediaEntry(id, sources: [source])
        
        self.partnerId = nil
    }
    
    init(_ title: String, id: String, partnerId: Int, ks: String? = nil, env: String? = nil) {
        self.id = id
        self.title = title
        self.partnerId = partnerId
        
        self.url = nil
        
        OVPMediaProvider(SimpleSessionProvider(serverURL: env ?? Item.defaultEnv, partnerId: Int64(partnerId), ks: ks))
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
    
    var items = [Item]()
    
    let itemPickerView = UIPickerView()
    
    let languageCodePickerView = UIPickerView()
    
    var selectedItem: Item! {
        didSet {
            do {
                let item = try cm.itemById(selectedItem.id)
                selectedDTGItem = item
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
    
    var selectedDTGItem: DTGItem?
    
    var selectedTextLanguageCode: String?
    var selectedAudioLanguageCode: String?
    
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var itemTextField: UITextField!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var languageCodeTextField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let jsonURL = Bundle.main.url(forResource: "items", withExtension: "json")!
//        let jsonURL = URL(string: "http://localhost/items.json")!
        let json = try! Data(contentsOf: jsonURL)
        let loadedItems = try! JSONDecoder().decode([ItemJSON].self, from: json)
        
        items = loadedItems.map{$0.toItem()}
        
        let completedItems = try! self.cm.itemsByState(.completed)
        for (index, item) in completedItems.enumerated() {
            if item.id.hasPrefix("test") && item.id.hasSuffix("()") {
                self.items.insert(Item(item.id, id: item.id, url: "file://foo.bar/baz"), at: index)
            }
        }

        cm.setDefaultAudioBitrateEstimation(bitrate: defaultAudioBitrateEstimation)

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
                
                var options: DTGSelectionOptions
                
                options = DTGSelectionOptions()
                    .setPreferredVideoHeight(300)
//                    .setPreferredVideoWidth(1000)
//                    .setPreferredVideoBitrates([.hevc(3_000_000), .avc1(5_000_000)])
//                    .setPreferredVideoBitrates([.hevc(300_000), .avc1(5_000_000)])
                    .setPreferredVideoCodecs([.hevc, .avc1])
                    .setPreferredAudioCodecs([.ac3, .mp4a])
                    .setAllTextLanguages()
//                    .setTextLanguages(["en"])
//                    .setAudioLanguages(["en", "ru"])
                    .setAllAudioLanguages()
                
                options.allowInefficientCodecs = true
                                
//                options = DTGSelectionOptions()
//                    .setTextLanguages(["he", "eng"])
//                    .setAudioLanguages(["fr", "de"])
//                    .setPreferredVideoHeight(600)
//                    .setPreferredVideoWidth(800)
//                
//                options = DTGSelectionOptions()
//                    .setPreferredVideoCodecs([.hevc])
//                    .setPreferredAudioCodecs([.ac3])
//                
//                options = DTGSelectionOptions()
//                    .setPreferredVideoBitrates([.hevc(10000000), .avc1(2000000)])
                
                
                
                
                
                
                try self.cm.loadItemMetadata(id: self.selectedItem.id, options: self.selectedItem.options)
//                try self.cm.loadItemMetadata(id: self.selectedItem.id, preferredVideoBitrate: 300000)
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
        self.view!.makeToast(message, duration: 0.6, position: CSToastPositionCenter)
    }
    
    func toastMedium(_ message: String) {
        print(message)
        self.view!.makeToast(message, duration: 1.0, position: CSToastPositionCenter)
    }
    
    func toastLong(_ message: String) {
        print(message)
        self.view!.makeToast(message, duration: 4, position: CSToastPositionCenter)
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
            guard let item = selectedDTGItem else { return 0 }
            if component == 0 {
                return item.selectedTextTracks.count
            } else {
                return item.selectedAudioTracks.count
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
            guard let item = selectedDTGItem else { return "" }
            if component == 0 {
                return item.selectedTextTracks[row].title
            } else {
                return item.selectedAudioTracks[row].title
            }
        } else {
            return items[row].title
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if pickerView === self.languageCodePickerView {
            guard let item = selectedDTGItem else { return }
            if component == 0 {
                guard item.selectedTextTracks.count > 0 else { return }
                self.selectedTextLanguageCode = item.selectedTextTracks[row].languageCode
            } else {
                guard item.selectedAudioTracks.count > 0 else { return }
                self.selectedAudioLanguageCode = item.selectedAudioTracks[row].languageCode
            }
            self.languageCodeTextField.text = "text code: \(self.selectedTextLanguageCode ?? ""), audio code: \(self.selectedAudioLanguageCode ?? "")"
        } else {
            self.itemTextField.text = items[row].title
            self.selectedItem = items[row]
        }
    }
}
