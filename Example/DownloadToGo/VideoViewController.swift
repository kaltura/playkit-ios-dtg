//
//  VideoViewController.swift
//  DownloadToGo
//
//  Created by Gal Orlanczyk on 13/07/2017.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import UIKit
import PlayKit

class VideoViewController: UIViewController {

    let controlsAnimationDuration = 0.4
    let trackViewControllerSegueIdentifier = "tracksViewController"
    
    var isControlsVisible = true
    var player: Player?
    var contentUrl: URL?
    var tracks: PKTracks?
    var selectedAudioTrack: Track?
    var selectedTextTrack: Track?
    var timer: Timer?
    
    @IBOutlet weak var playerView: PlayerView!
    @IBOutlet weak var playheadSlider: UISlider!
    @IBOutlet weak var controlsView: UIVisualEffectView!
    @IBOutlet weak var controlsViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var controlsViewBottomConstraint: NSLayoutConstraint!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let player = try? PlayKitManager.shared.loadPlayer(pluginConfig: nil) {
            self.player = player
            player.view = self.playerView
            player.prepare(MediaConfig(mediaEntry: MediaEntry("id", sources: [MediaSource("id", contentUrl: contentUrl)])))
            
            player.addObserver(self, event: PlayerEvent.tracksAvailable) { [weak self] (event) in
                self?.tracks = event.tracks
            }
            player.addObserver(self, event: PlayerEvent.playing) { [weak self] (event) in
                guard let strongSelf = self else { return }
                strongSelf.stopTimer()
                strongSelf.timer = Timer.scheduledTimer(timeInterval: 0.5, target: strongSelf, selector: #selector(strongSelf.timerTick), userInfo: nil, repeats: true)
            }
        } else {
            print("error: failed to create player")
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.player?.isPlaying == true {
            self.timer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(self.timerTick), userInfo: nil, repeats: true)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.stopTimer()
    }
    
    @IBAction func playerViewTapped(_ sender: UITapGestureRecognizer) {
        if isControlsVisible {
            self.navigationController?.setNavigationBarHidden(true, animated: true)
            UIView.animate(withDuration: self.controlsAnimationDuration, delay: 0, options: .curveEaseOut, animations: {
                self.controlsViewBottomConstraint.constant = -self.controlsViewHeightConstraint.constant
                self.view.layoutIfNeeded()
            }, completion: { (finished) in
                self.controlsView.isHidden = true
            })
        } else {
            self.navigationController?.setNavigationBarHidden(false, animated: true)
            UIView.animate(withDuration: self.controlsAnimationDuration, delay: 0, options: .curveEaseOut, animations: {
                self.controlsViewBottomConstraint.constant = 0
                self.controlsView.isHidden = false
                self.view.layoutIfNeeded()
            }, completion: nil)
        }
        self.isControlsVisible = !self.isControlsVisible
    }

    @IBAction func playheadTouchDown(_ sender: UISlider) {
        // when playhead selected stop the timer
        self.stopTimer()
    }
    
    @IBAction func playheadValueChanged(_ sender: UISlider) {
        // when playhead value changed seek to time
        guard let player = self.player else { return }
        player.currentTime = Double(self.playheadSlider.value) * player.duration
    }

    @IBAction func playTouched(_ sender: UIButton) {
        self.player?.play()
    }
    
    @IBAction func pauseTouched(_ sender: UIButton) {
        self.player?.pause()
        self.stopTimer()
    }
 
    func timerTick() {
        guard let player = self.player else { return }
        self.playheadSlider.value = Float(player.currentTime) / Float(player.duration)
    }
    
    private func stopTimer() {
        self.timer?.invalidate()
        self.timer = nil
    }
}

/************************************************************/
// MARK: - Navigation
/************************************************************/

extension VideoViewController {
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        if identifier == self.trackViewControllerSegueIdentifier {
            if let _ = self.tracks {
                return true
            }
            return false
        }
        return true
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == self.trackViewControllerSegueIdentifier {
            let destinationVC = (segue.destination as! UINavigationController).topViewController as! TracksViewController
            destinationVC.player = self.player
            destinationVC.tracks = self.tracks
            destinationVC.selectedAudioTrack = self.selectedAudioTrack
            destinationVC.selectedTextTrack = self.selectedTextTrack
            destinationVC.delegate = self
            destinationVC.popoverPresentationController?.delegate = self
        }
    }
}

/************************************************************/
// MARK: - UIAdaptivePresentationControllerDelegate
/************************************************************/

extension VideoViewController: UIPopoverPresentationControllerDelegate {
    
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .fullScreen
    }
    
    
}

/************************************************************/
// MARK: - TracksViewControllerDelegate
/************************************************************/

extension VideoViewController: TracksViewControllerDelegate {
    
    func trackViewControllerDidSelectAudioTrack(_ audioTrack: Track?, andTextTrack textTrack: Track?) {
        self.selectedAudioTrack = audioTrack
        self.selectedTextTrack = textTrack
        
        if audioTrack != nil {
            self.player?.selectTrack(trackId: audioTrack!.id)
        }
        if textTrack != nil {
            self.player?.selectTrack(trackId: textTrack!.id)
        }
    }
}
