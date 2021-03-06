
import UIKit
import ImageScrollView

class ImageDetailViewController: UIViewController, Storyboarded {
    
    @IBOutlet var imageScrollView: ImageScrollView!
    
    var image: UIImage?
        
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.backgroundColor = #colorLiteral(red: 0.0862745098, green: 0.0862745098, blue: 0.09411764706, alpha: 1)
        imageScrollView.backgroundColor = #colorLiteral(red: 0.0862745098, green: 0.0862745098, blue: 0.09411764706, alpha: 1)
        imageScrollView.setup()
        guard let image = image else { return }
        imageScrollView.display(image: image)
    }
}
