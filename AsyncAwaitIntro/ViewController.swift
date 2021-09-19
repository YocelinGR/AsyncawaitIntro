//
//  ViewController.swift
//  AsyncAwaitIntro
//
//  Created by Andy Ibanez on 6/12/21.
//

import UIKit

// MARK: - Definitions

struct ImageMetadata: Codable {
    let name: String
    let firstAppearance: String
    let year: Int
}

struct DetailedImage {
    let image: UIImage
    let metadata: ImageMetadata
}

enum ImageDownloadError: Error {
    case badImage
    case invalidMetadata
}

struct Character {
    let id: Int
    
    var metadata: ImageMetadata {
        get async throws {
            let metadata = try await downloadMetadata(for: id)
            return metadata
        }
    }
    
    var image: UIImage {
        get async throws {
            return try await downloadImage(imageNumber: id)
        }
    }
}

// MARK: - Functions

func downloadImageAndMetadata(imageNumber: Int) async throws -> DetailedImage {
    let image = try await downloadImage(imageNumber: imageNumber)
    let metadata = try await downloadMetadata(for: imageNumber)
    return DetailedImage(image: image, metadata: metadata)
}

func downloadImage(imageNumber: Int) async throws -> UIImage {
    let imageUrl = URL(string: "https://www.andyibanez.com/fairesepages.github.io/tutorials/async-await/part1/\(imageNumber).png")!
    let imageRequest = URLRequest(url: imageUrl)
    let (data, imageResponse) = try await URLSession.shared.data(for: imageRequest)
    guard let image = UIImage(data: data), (imageResponse as? HTTPURLResponse)?.statusCode == 200 else {
        throw ImageDownloadError.badImage
    }
    return image
}

func downloadMetadata(for id: Int) async throws -> ImageMetadata {
    let metadataUrl = URL(string: "https://www.andyibanez.com/fairesepages.github.io/tutorials/async-await/part1/\(id).json")!
    let metadataRequest = URLRequest(url: metadataUrl)
    let (data, metadataResponse) = try await URLSession.shared.data(for: metadataRequest)
    guard (metadataResponse as? HTTPURLResponse)?.statusCode == 200 else {
        throw ImageDownloadError.invalidMetadata
    }
    
    return try JSONDecoder().decode(ImageMetadata.self, from: data)
}

func downloadImageAndMetadata(
    imageNumber: Int,
    completionHandler: @escaping (_ image: DetailedImage?, _ error: Error?) -> Void
) {
    let imageUrl = URL(string: "https://www.andyibanez.com/fairesepages.github.io/tutorials/async-await/part1/\(imageNumber).png")!
    let imageTask = URLSession.shared.dataTask(with: imageUrl) { data, response, error in
        guard let data = data, let image = UIImage(data: data), (response as? HTTPURLResponse)?.statusCode == 200 else {
            completionHandler(nil, ImageDownloadError.badImage)
            return
        }
        let metadataUrl = URL(string: "https://www.andyibanez.com/fairesepages.github.io/tutorials/async-await/part1/\(imageNumber).json")!
        let metadataTask = URLSession.shared.dataTask(with: metadataUrl) { data, response, error in
            guard let data = data, let metadata = try? JSONDecoder().decode(ImageMetadata.self, from: data),  (response as? HTTPURLResponse)?.statusCode == 200 else {
                completionHandler(nil, ImageDownloadError.invalidMetadata)
                return
            }
            let detailedImage = DetailedImage(image: image, metadata: metadata)
            completionHandler(detailedImage, nil)
        }
        metadataTask.resume()
    }
    imageTask.resume()
}

// MARK: - Main class

class ViewController: UIViewController {
    
    @IBOutlet weak var imageView: UIImageView!
    
    @IBOutlet weak var metadata: UILabel!
    
    var anImage: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
    
    @MainActor override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // MARK: METHOD 1 - Using Async/Await
        
        Task {
            if let imageDetail = try? await downloadImageAndMetadata(imageNumber: 1) {
                self.imageView.image = imageDetail.image
                self.metadata.text = "\(imageDetail.metadata.name) (\(imageDetail.metadata.firstAppearance) - \(imageDetail.metadata.year))"
            }
        }
    }
    
}
