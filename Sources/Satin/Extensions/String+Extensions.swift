//
//  String+Extensions.swift
//  Satin
//
//  Created by Reza Ali on 4/19/20.
//

import Foundation

// Partial Fix for https://github.com/Fabric-Project/Satin/issues/15
var TitleCaseStringCache = [String:String ]()

private let TitleCaseStringCacheQueue = DispatchQueue(label: "fabric.titleCaseStringCacheQueue")

public extension String {
    var camelCase: String {
        var parts = split(separator: " ")
        if let first = parts.first {
            let upperChars = first.prefix(while: { $0.isUppercase }).lowercased()
            parts[0] = upperChars + Substring(first.dropFirst(upperChars.count))
        }
        return parts.joined()
    }

    var titleCase: String {
        
        return TitleCaseStringCacheQueue.asyncAndWait {
            
            // Partial Fix for https://github.com/Fabric-Project/Satin/issues/15
            if let cached = TitleCaseStringCache[self] {
                return cached
            } else {
                var titleCase = self.replacingOccurrences(of: "(?<![A-Z])([A-Z][a-z])",
                                                     with: " $1",
                                                     options: .regularExpression,
                                                     range: range(of: self))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Capitalize the first letter of each word, unless the word is all caps (acronym)
                titleCase = titleCase
                           .split(separator: " ")
                           .map { word in
                               let s = String(word)
                               if s.uppercased() == s { return s }       // Keep acronyms
                               return s.prefix(1).uppercased() + s.dropFirst()
                           }
                           .joined(separator: " ")
                
                TitleCaseStringCache[self] = titleCase
                
                return titleCase
            }
        }
    }
}
