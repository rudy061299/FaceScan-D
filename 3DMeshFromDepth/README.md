# Reference notes

### User Interface

* In `Presentation/MainViewController.swift`, the function `viewDidLoad` on line [26](https://github.com/rudy061299/FaceScan-D/blob/main/3DMeshFromDepth/Presentation/MainViewController.swift#L26) is executed the first time the app is opened. It sets up the Metal view and UI elements like buttons by calling on functions like `setupMtkView`, `setupSaveButton` etc.
* All UI elements are set up programmatically rather than using Storyboard. For example, in the function `setupMtkView`, an instance of `MTKView()` called `mtkView` is set up and added to the main `View` as a `Subview`. To cater to displays of all sizes the constraints of `mtkView` are anchored to the left, right, top, and bottom of the detected screen size.
* 

### Point Cloud capturing mechanism
