//
//  TracksViewController.swift
//  DownloadToGo
//
//  Created by Gal Orlanczyk on 13/07/2017.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import UIKit
import PlayKit

protocol TracksViewControllerDelegate: class {
    func trackViewControllerDidSelectAudioTrack(_ audioTrack: Track?, andTextTrack textTrack: Track?)
}

class TracksViewController: UITableViewController {

    weak var delegate: TracksViewControllerDelegate?
    weak var player: Player?
    weak var tracks: PKTracks!
    weak var selectedAudioTrack: Track?
    weak var selectedTextTrack: Track?
    
    var lastSelectedAudioTrackIndexPath: IndexPath?
    var lastSelectedTextTrackIndexPath: IndexPath?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.setRightBarButton(UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissTracksVC)), animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.delegate?.trackViewControllerDidSelectAudioTrack(self.selectedAudioTrack, andTextTrack: self.selectedTextTrack)
    }
    
    func dismissTracksVC() {
        self.dismiss(animated: true, completion: nil)
    }
    
    /************************************************************/
    // MARK: - UITableViewDataSource
    /************************************************************/
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return self.tracks.audioTracks?.count ?? 0
        } else {
            return self.tracks.textTracks?.count ?? 0
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        var numberOfSections = 0
        if let _ = self.tracks.audioTracks {
            numberOfSections += 1
        }
        if let _ = self.tracks.textTracks {
            numberOfSections += 1
        }
        return numberOfSections
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "trackCell", for: indexPath)
        
        var title: String? = nil
        if indexPath.section == 0 {
            if let audioTrack = self.tracks.audioTracks?[indexPath.row] {
                if let selectedAudioTrack = self.selectedAudioTrack, selectedAudioTrack.isEqual(rhs: audioTrack) {
                    cell.accessoryType = .checkmark
                    self.lastSelectedAudioTrackIndexPath = indexPath
                }
                title = audioTrack.title
            }
        } else {
            if let textTrack = self.tracks.textTracks?[indexPath.row] {
                if let selectedTextTrack = self.selectedTextTrack, selectedTextTrack.isEqual(rhs: textTrack) {
                    cell.accessoryType = .checkmark
                    self.lastSelectedTextTrackIndexPath = indexPath
                }
                title = textTrack.title
            }
        }
        
        cell.textLabel?.text = title
        
        return cell
    }
   
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "Audio Tracks"
        } else {
            return "Text Tracks"
        }
    }
    
    /************************************************************/
    // MARK: - UITableViewDelegate
    /************************************************************/
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            // remove last selected checkmark
            if let lastSelectedAudio = self.lastSelectedAudioTrackIndexPath {
                self.tableView.cellForRow(at: lastSelectedAudio)?.accessoryType = .none
            }
            if self.lastSelectedAudioTrackIndexPath != indexPath {
                self.lastSelectedAudioTrackIndexPath = indexPath
                self.selectedAudioTrack = self.tracks.audioTracks?[indexPath.row]
            }
        } else {
            // remove last selected checkmark
            if let lastSelectedText = self.lastSelectedTextTrackIndexPath {
                self.tableView.cellForRow(at: lastSelectedText)?.accessoryType = .none
            }
            if self.lastSelectedTextTrackIndexPath != indexPath {
                self.lastSelectedTextTrackIndexPath = indexPath
                self.selectedTextTrack = self.tracks.textTracks?[indexPath.row]
            }
        }
        self.tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
    }
}
