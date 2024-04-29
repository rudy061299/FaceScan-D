//
//  AppCoordinator.swift
//  3DMeshFromDepth
//

import UIKit
import ARKit

class AppCoordinator {
    
    func presentArSessionErrorAlert(in vc: UIViewController, with session: ARSession, and error: Error) {
        guard error is ARError else { return }
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
        let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
            alertController.dismiss(animated: true, completion: nil)
            if let configuration = session.configuration {
                session.run(configuration, options: .resetSceneReconstruction)
            }
        }
        alertController.addAction(restartAction)
        alertController.modalPresentationStyle = .formSheet
        alertController.preferredContentSize = CGSize(width: vc.view.frame.width, height: vc.view.frame.height)
        vc.present(alertController, animated: true, completion: nil)
    }
    
    func presentDoneAlert(in vc: MainViewController) {
        let alert = UIAlertController(title: "Scan saved", message: nil, preferredStyle: .alert)
        alert.modalPresentationStyle = .formSheet
        alert.preferredContentSize = CGSize(width: vc.view.frame.width, height: vc.view.frame.height)
        vc.present(alert, animated: true, completion: nil)
    }
    
    func export(in vc: MainViewController, with url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url as Any], applicationActivities: .none)
        vc.dismiss(animated: true)
        activityVC.modalPresentationStyle = .formSheet
        activityVC.preferredContentSize = CGSize(width: vc.view.frame.width, height: vc.view.frame.height)
        vc.present(activityVC, animated: true)
    }
}
