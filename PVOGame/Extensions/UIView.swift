import UIKit

extension UIView {

    func sizeToFitCustom () {
        var size = CGSize(width: 0, height: 0)
        for view in self.subviews {
            let frame = view.frame
            let newW = frame.origin.x + frame.width
            let newH = frame.origin.y + frame.height
            if newW > size.width {
                size.width = newW
            }
            if newH > size.height {
                size.height = newH
            }
        }
        self.frame.size = size
    }

}
