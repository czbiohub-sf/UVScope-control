# UVScope-control
UVScope control software

## Intro
Thanks for visiting UVScope-control! Feel free to comment and make PRs in a constructive manner to help improve this project. Although it's been used to acquire hundreds of thousands of images (without errors) as part of dozens of multi-dimensional (MD) image acquisition experiments, it's likely that many bugs still exist because this software has only been tested in very narrow operating conditions, by only one user. 

UVScope-control was written to control a custom ultraviolet microscope built at Chan Zuckerberg Biohub, but could be adapted to control other microscopes by replacing device-specific hardware drivers. The microscope has a main control class, but works together with other modules to control a camera, XY stage, focus stage, and multiplexed LEDs with hardware sync module. A multi-dimensional image storage and processing class, MDImage, ingests images from the microscope, saving them to disk and/or memory in real time, in a format that can easily be re-loaded later into memory. MDImage also has a 6D image viewer built-in for quickly browsing image data.

Link to our published manuscript: https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1009257

## Modules

### UVScope
- Orchestrates hardware drivers
- Implements:
  - A GUI for user control
  - Manual image snapping and previewing via Matlab's Image Acquisition toolbox
  - A 'runMDA' method that allows it to be driven by an external object implementing a MD acquisition
  - Active focus tracking over time, and across large areas of a sample.
  #### 

### MDEngine
- Runs a simple state machine
- Keeps track of MD acquisition parameters 
- Sends commands to UVScope for MD image acquisitions (XY positions, Z-position (offsets), Z-stacks, Channels, Time points)
- Feeds images to an MDImage object

### MDImage
- I/O for large imaging datasets
- Manipulation of 6D imaging datasets
- Implements the following image processing operations on large 6D datasets:
  - Digital re-focusing
  - Image stack alignment via cross-correlation
  - Timeseries drift correction via cross-correlation
  - Full transport of intensity (TIE) solver with non-uniform illumination
  - Richardson-Lucy image deconvolution (3D)
  - Flatfield illumination correction
  - Image registration between channels (affine transformation)
  
## How it works
![UVScope](https://github.com/czbiohub/UVScope-control/blob/master/Images/UVScope%20Software%20architecture.png)

## Microscope wiring diagram
![WiringDiagram](https://github.com/czbiohub/UVScope-control/blob/master/Images/UV%20scope%20wiring%20diagram.png)
