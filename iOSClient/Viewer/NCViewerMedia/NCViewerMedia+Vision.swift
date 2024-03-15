//
//  NCViewerMedia+Vision.swift
//  Nextcloud
//
//  Created by Milen on 15.03.24.
//  Copyright © 2024 Marino Faggiana. All rights reserved.
//

import Foundation
import Vision

extension NCViewerMedia {
    /// - Tag: PreprocessImage
    func scaleAndOrient(image: UIImage) -> UIImage {

        // Set a default value for limiting image size.
        let maxResolution: CGFloat = 640

        guard let cgImage = image.cgImage else {
            print("UIImage has no CGImage backing it!")
            return image
        }

        // Compute parameters for transform.
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        var transform = CGAffineTransform.identity

        var bounds = CGRect(x: 0, y: 0, width: width, height: height)

        if width > maxResolution ||
            height > maxResolution {
            let ratio = width / height
            if width > height {
                bounds.size.width = maxResolution
                bounds.size.height = round(maxResolution / ratio)
            } else {
                bounds.size.width = round(maxResolution * ratio)
                bounds.size.height = maxResolution
            }
        }

        let scaleRatio = bounds.size.width / width
        let orientation = image.imageOrientation
        switch orientation {
        case .up:
            transform = .identity
        case .down:
            transform = CGAffineTransform(translationX: width, y: height).rotated(by: .pi)
        case .left:
            let boundsHeight = bounds.size.height
            bounds.size.height = bounds.size.width
            bounds.size.width = boundsHeight
            transform = CGAffineTransform(translationX: 0, y: width).rotated(by: 3.0 * .pi / 2.0)
        case .right:
            let boundsHeight = bounds.size.height
            bounds.size.height = bounds.size.width
            bounds.size.width = boundsHeight
            transform = CGAffineTransform(translationX: height, y: 0).rotated(by: .pi / 2.0)
        case .upMirrored:
            transform = CGAffineTransform(translationX: width, y: 0).scaledBy(x: -1, y: 1)
        case .downMirrored:
            transform = CGAffineTransform(translationX: 0, y: height).scaledBy(x: 1, y: -1)
        case .leftMirrored:
            let boundsHeight = bounds.size.height
            bounds.size.height = bounds.size.width
            bounds.size.width = boundsHeight
            transform = CGAffineTransform(translationX: height, y: width).scaledBy(x: -1, y: 1).rotated(by: 3.0 * .pi / 2.0)
        case .rightMirrored:
            let boundsHeight = bounds.size.height
            bounds.size.height = bounds.size.width
            bounds.size.width = boundsHeight
            transform = CGAffineTransform(scaleX: -1, y: 1).rotated(by: .pi / 2.0)
        default:
            transform = .identity
        }

        return UIGraphicsImageRenderer(size: bounds.size).image { rendererContext in
            let context = rendererContext.cgContext

            if orientation == .right || orientation == .left {
                context.scaleBy(x: -scaleRatio, y: scaleRatio)
                context.translateBy(x: -height, y: 0)
            } else {
                context.scaleBy(x: scaleRatio, y: -scaleRatio)
                context.translateBy(x: 0, y: -height)
            }
            context.concatenate(transform)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func recognizeTextHandler(request: VNRequest, error: Error?) {
        // Perform drawing on the main thread.
//        DispatchQueue.main.async {
//            guard let drawLayer = self.pathLayer,
//                  let results = request.results as? [VNTextObservation] else {
//                    return
//            }
//            self.draw(text: results, onImageWithBounds: drawLayer.bounds)
//            drawLayer.setNeedsDisplay()
//        }

        let size = CGSize(width: image!.cgImage!.width, height: image!.cgImage!.height) // note, in pixels from `cgImage`; this assumes you have already rotate, too
        let bounds = CGRect(origin: .zero, size: size)

        guard let results = request.results as? [VNRecognizedTextObservation], error == nil else { return }

        let rects = results.map {
            convert(boundingBox: $0.boundingBox, to: CGRect(origin: .zero, size: size))
        }

        let string = results.compactMap {
            $0.topCandidates(1).first?.string
        }.joined(separator: "\n")

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let final = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            image!.draw(in: bounds)
            UIColor.red.setStroke()
            for rect in rects {
                let path = UIBezierPath(rect: rect)
                path.lineWidth = 5
                path.stroke()
            }
        }

        DispatchQueue.main.async { [self] in
            imageVideoContainer.image = final
            //                    label.text = string
        }
    }

    func convert(boundingBox: CGRect, to bounds: CGRect) -> CGRect {
        let imageWidth = bounds.width
        let imageHeight = bounds.height

        // Begin with input rect.
        var rect = boundingBox

        // Reposition origin.
        rect.origin.x *= imageWidth
        rect.origin.x += bounds.minX
        rect.origin.y = (1 - rect.maxY) * imageHeight + bounds.minY

        // Rescale normalized coordinates.
        rect.size.width *= imageWidth
        rect.size.height *= imageHeight

        return rect
    }


    // Lines of text are RED.  Individual characters are PURPLE.
    private func draw(text: [VNTextObservation], onImageWithBounds bounds: CGRect) {
        CATransaction.begin()
        for wordObservation in text {
            let wordBox = boundingBox(forRegionOfInterest: wordObservation.boundingBox, withinImageBounds: bounds)
            let wordLayer = shapeLayer(color: .red, frame: wordBox)

            // Add to pathLayer on top of image.
            pathLayer?.addSublayer(wordLayer)

            // Iterate through each character within the word and draw its box.
            guard let charBoxes = wordObservation.characterBoxes else {
                continue
            }
            for charObservation in charBoxes {
                let charBox = boundingBox(forRegionOfInterest: charObservation.boundingBox, withinImageBounds: bounds)
                let charLayer = shapeLayer(color: .purple, frame: charBox)
                charLayer.borderWidth = 1

                // Add to pathLayer on top of image.
                pathLayer?.addSublayer(charLayer)
            }
        }
        CATransaction.commit()
    }

    private func boundingBox(forRegionOfInterest: CGRect, withinImageBounds bounds: CGRect) -> CGRect {

        let imageWidth = bounds.width
        let imageHeight = bounds.height

        // Begin with input rect.
        var rect = forRegionOfInterest

        // Reposition origin.
        rect.origin.x *= imageWidth
        rect.origin.x += bounds.origin.x
        rect.origin.y = (1 - rect.origin.y) * imageHeight + bounds.origin.y

        // Rescale normalized coordinates.
        rect.size.width *= imageWidth
        rect.size.height *= imageHeight

        return rect
    }

    private func shapeLayer(color: UIColor, frame: CGRect) -> CAShapeLayer {
        // Create a new layer.
        let layer = CAShapeLayer()

        // Configure layer's appearance.
        layer.fillColor = nil // No fill to show boxed object
        layer.shadowOpacity = 0
        layer.shadowRadius = 0
        layer.borderWidth = 2

        // Vary the line color according to input.
        layer.borderColor = color.cgColor

        // Locate the layer.
        layer.anchorPoint = .zero
        layer.frame = frame
        layer.masksToBounds = true

        // Transform the layer to have same coordinate system as the imageView underneath it.
        layer.transform = CATransform3DMakeScale(1, -1, 1)

        return layer
    }

//    func convert(boundingBox: CGRect, to bounds: CGRect) -> CGRect {
//        let imageWidth = bounds.width
//        let imageHeight = bounds.height
//
//        // Begin with input rect.
//        var rect = boundingBox
//
//        // Reposition origin.
//        rect.origin.x *= imageWidth
//        rect.origin.x += bounds.minX
//        rect.origin.y = (1 - rect.maxY) * imageHeight + bounds.minY
//
//        // Rescale normalized coordinates.
//        rect.size.width *= imageWidth
//        rect.size.height *= imageHeight
//
//        return rect
//    }

//    // Draws groups of colored boxes.
//    func show(boxGroups: [ColoredBoxGroup]) {
//        DispatchQueue.main.async {
//            let layer = self.previewView.videoPreviewLayer
//            self.removeBoxes()
//            for boxGroup in boxGroups {
//                let color = boxGroup.color
//                for box in boxGroup.boxes {
//                    let rect = layer.layerRectConverted(fromMetadataOutputRect: box.applying(self.visionToAVFTransform))
//                    self.draw(rect: rect, color: color.cgColor)
//                }
//            }
//        }
//    }

    // Draw a box on the screen, which must be done the main queue.
//    var boxLayer = [CAShapeLayer]()
//    func draw(rect: CGRect, color: CGColor) {
//        let layer = CAShapeLayer()
//        layer.opacity = 0.5
//        layer.borderColor = color
//        layer.borderWidth = 1
//        layer.frame = rect
//        boxLayer.append(layer)
//        self.view.layer.insertSublayer(layer, at: 1)
//    }

}
