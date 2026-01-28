// ImgVariant.swift
// Vestivia
//
// Cloudflare Images variant names used by the app.
// These values must match the variant names configured in Cloudflare (case-sensitive).

import Foundation

public enum ImgVariant: String, Codable {
    /// Grid / search results thumbnails — Cloudflare variant is named "Thumbnail"
    case thumbnail = "Thumbnail"
    /// Listing detail card-size image — Cloudflare variant is named "Card"
    case card = "Card"

    /// Optional helper if you ever need a path segment or to display the name
    public var name: String { rawValue }
}
