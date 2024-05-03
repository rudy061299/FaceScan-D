# iOS Face Scan

This project uses Swift, ARKit, and Metal to capture a 3D point cloud of a face through the True Depth front camera in iPhones/iPads.

## Setting it up

1. Git clone the project through the command line using `git clone https://github.com/rudy061299/FaceScan-D.git`
2. Open the project file using Xcode.
3. Click on the topmost folder in XCode's left-hand file view section. Navigate to `Signing & Capabilities` and change the `Team` to your own Apple Developer account, as well as assign a new `Bundle Identifier`.
4. Connect your iPad to the Macbook using a cable. 
5. From the Xcode menu, navigate to `Window` -> `Devices and Simulators`. You should be able to see the connected iPad's name. For the first run, Xcode will take some time to configure the iPad. Wait for Xcode to indicate that the connected iPad is ready.
6. Once the iPad has been configured by Xcode, build the app using the run button in the top bar of the left section of Xcode.
7. You can see the app being installed on the iPad; however, it will give you an error message saying that the app is unverified. On your iPad, navigate to `Settings` -> `General` -> `General` -> `VPN & Device Management`. You can trust and verify the app from here.
8. Run the app again on Xcode, and it should run successfully on the connected iPad.
