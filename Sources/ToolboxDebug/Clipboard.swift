//
//  Clipboard.swift
//  ToolboxDebug
//

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum Clipboard {
  static func copy(_ string: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = string
    #elseif canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
    #endif
  }
}
