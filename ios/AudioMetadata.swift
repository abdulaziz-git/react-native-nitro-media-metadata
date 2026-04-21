//
//  AudioMetadata.swift
//  NitroMediaMetadata
//
//  Created by Yogesh on 06/02/26.
//

import Foundation
import AVFoundation

public class AudioMetadata {
  public static func getAudioInfo(from sourceURL: URL, options: VideoMetadata.Options = VideoMetadata.Options()) throws -> [String: Any] {
    var assetOptions: [String: Any] = [:]
    if !sourceURL.isFileURL && sourceURL.scheme != "ph" {
      assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = options.headers
    }
    let asset = AVURLAsset(url: sourceURL, options: assetOptions)
    
    let semaphore = DispatchSemaphore(value: 0)
    asset.loadValuesAsynchronously(forKeys: ["tracks", "duration", "metadata"]) {
      semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 10)

    var error: NSError?
    let durationStatus = asset.statusOfValue(forKey: "duration", error: &error)
    if durationStatus != .loaded {
      throw error ?? NSError(domain: "AudioMetadata", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load audio duration (Status: \(durationStatus.rawValue))"])
    }

    let duration = CMTimeGetSeconds(asset.duration)
    
    var fileSize: Int64 = 0
    if sourceURL.isFileURL,
       let fileAttributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
       let size = fileAttributes[.size] as? NSNumber {
      fileSize = size.int64Value
    }

    var bitrate: Float = 0
    var sampleRate: Double = 0
    var channels: Int = 0
    var codec = ""
    var artist = ""
    var title = ""
    var album = ""
    var year = ""
    var trackNumber = ""
    var genre = ""
    var artwork = ""

    if let audioTrack = asset.tracks(withMediaType: .audio).first {
        bitrate = audioTrack.estimatedDataRate
        if let formatDesc = audioTrack.formatDescriptions.first {
            let description = formatDesc as! CMFormatDescription
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                sampleRate = asbd.mSampleRate
                channels = Int(asbd.mChannelsPerFrame)
            }
            let codecType = CMFormatDescriptionGetMediaSubType(description)
            codec = fourCharCodeToString(fourCharCode: codecType)
        }
    }

    for item in asset.metadata {
        guard let value = item.value else { continue }

        if let key = item.commonKey?.rawValue {
            switch key {
            case AVMetadataKey.commonKeyArtist.rawValue:
                artist = value as? String ?? ""
            case AVMetadataKey.commonKeyTitle.rawValue:
                title = value as? String ?? ""
            case AVMetadataKey.commonKeyAlbumName.rawValue:
                album = value as? String ?? ""
            case AVMetadataKey.commonKeyArtwork.rawValue:
                if let data = value as? Data {
                    artwork = data.base64EncodedString()
                }
            default:
                break
            }
        }

        if let identifier = item.identifier {
            switch identifier {
            case AVMetadataIdentifier.id3MetadataYear,
                 AVMetadataIdentifier.iTunesMetadataReleaseDate:
                year = value as? String ?? ""
            case AVMetadataIdentifier.id3MetadataTrackNumber:
                if let str = value as? String {
                    trackNumber = str
                } else if let num = value as? NSNumber {
                    trackNumber = num.stringValue
                }
            case AVMetadataIdentifier.id3MetadataContentType,
                 AVMetadataIdentifier.iTunesMetadataUserGenre:
                genre = value as? String ?? ""
            default:
                break
            }
        }
    }

    return [
      "duration": duration,
      "fileSize": fileSize,
      "codec": codec,
      "sampleRate": sampleRate,
      "channels": channels,
      "bitRate": bitrate,
      "artist": artist,
      "title": title,
      "album": album,
      "year": year,
      "trackNumber": trackNumber,
      "genre": genre,
      "artwork": artwork
    ]
  }

  private static func fourCharCodeToString(fourCharCode: FourCharCode) -> String {
    let bytes: [UInt8] = [
      UInt8((fourCharCode >> 24) & 0xFF),
      UInt8((fourCharCode >> 16) & 0xFF),
      UInt8((fourCharCode >> 8) & 0xFF),
      UInt8(fourCharCode & 0xFF)
    ]
    
    return bytes.compactMap { byte in
      let c = Character(UnicodeScalar(byte))
      return c.isASCII ? String(c) : nil
    }.joined().trimmingCharacters(in: .whitespaces)
  }
}
