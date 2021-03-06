//
//  FileAnalysis.swift
//  CodeObfuscation
//
//  Created by hejunqiu on 2017/6/6.
//  Copyright © 2017年 CHE. All rights reserved.
//

import Foundation

struct FileAnalysis {
    fileprivate var filepaths: Array<String>
    public var cohFilepath: String
    public var clazzs = [String: Class]()
    public var outStream: FileOutStream?

    init(filepaths fps: Array<String>, writtenFilepath wfp: String) {
        filepaths = fps
        cohFilepath = wfp
        outStream = FileOutStream.init(filepath: cohFilepath)
    }
}

extension FileAnalysis {
    mutating func start() {
        outStream?.read()
        for filepath in self.filepaths {
            do {
                let filecontent = try NSString(contentsOfFile: filepath, encoding: String.Encoding.utf8.rawValue)
                if self.outStream?.worthParsingFile(filecontent as String, filename: (filepath as NSString).lastPathComponent) == true {
                    self.analysisClassWithString(classString: filecontent)
                }
            } catch {
                print(error)
            }
        }
    }

    private mutating func analysisClassWithString(classString: NSString) {
        let scanner = Scanner(string: classString as String)
        scanner.charactersToBeSkipped = NSCharacterSet.whitespacesAndNewlines
        var scannedStrings = [String]()
        var start : Int
        while scanner.scanUpTo("@interface", into: nil) {
            start = scanner.scanLocation
            if !scanner.scanUpTo("CO_CONFUSION_CLASS", into: nil) {
                continue
            }
            scanner.scanString("CO_CONFUSION_CLASS", into: nil)
            var classname : NSString?
            if scanner.scanUpTo(":", into: &classname) {
                scanner.scanString(":", into: nil)
                var supername : NSString?
                if !scanner.scanUpToCharacters(from: NSCharacterSet.whitespacesAndNewlines, into: &supername) {
                    print("Code exists error!")
                    exit(-1)
                }
                classname = classname?.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines) as NSString?
                if let clazzName = classname as String!, let superName = supername as String! {
                    let clazz = Class(classname: clazzName, supername: superName)
                    let location_start = scanner.scanLocation
                    scanner.scanUpTo("@end", into: nil)
                    let classDescribeString = classString.substring(with: NSMakeRange(location_start, scanner.scanLocation - location_start))
                    self.analysisFileWithString(classDescribeString, into: clazz, methodFlag: ";");
                    self.clazzs[clazzName] = clazz

                    // TODO: 需要实现下面这个函数
                    registerClassRelationship(class: clazzName, super: superName)

                    scanner.scanString("@end", into: nil)
                    scannedStrings.append(classString.substring(with: NSMakeRange(start, scanner.scanLocation - start)))
                }
            }
        }
        var restString  = classString
        for str in scannedStrings {
            restString = restString.replacingOccurrences(of: str, with: "") as NSString
        }
        self.analysisCategoryAndExtensions(restString)
        self.analysisImplementation(restString)
    }

    private mutating func analysisCategoryAndExtensions(_ str: NSString) {
        let scanner = Scanner(string: str as String)
        while scanner.scanUpTo("@interface", into: nil), !scanner.isAtEnd {
            scanner.charactersToBeSkipped = NSCharacterSet.whitespacesAndNewlines
            scanner.scanString("@interface", into: nil)
            var classname : NSString?
            if scanner.scanUpTo("(", into: &classname) {
                if !scanner.scanUpTo("CO_CONFUSION_CATEGORY", into: nil) {
                    continue
                }
                scanner.scanString("CO_CONFUSION_CATEGORY", into: nil)
                classname = classname?.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines) as NSString?
                if let clazzName = classname as String? {
                    var category : NSString?
                    var clazz : Class?
                    if scanner.scanUpTo(")", into: &category) {
                        if category?.length == 0 { // 这是扩展。扩展必须从已有的分析的字典里取；否则报错
                            clazz = self.clazzs[clazzName]
                            if clazz == nil {
                                print("类扩展\(clazzName): 还没有相应的类")
                                exit(-1)
                            }
                        } else { // 这是类别。类别可以自建分析内容
                            if let _category = category as String? {
                                let identifier = String.init(format: "%@ (%@)", clazzName, _category)
                                clazz = self.clazzs[identifier]
                                if clazz == nil {
                                    clazz = Class.init(classname: clazzName, supername: nil)
                                    clazz!.categoryname = _category
                                    self.clazzs[identifier] = clazz!
                                }
                            }
                        }
                    }
                    if clazz != nil {
                        let location_start = scanner.scanLocation
                        scanner.scanUpTo("@end", into: nil)
                        let classDescribeString = str.substring(with: NSMakeRange(location_start, scanner.scanLocation - location_start))
                        self.analysisFileWithString(classDescribeString, into: clazz!, methodFlag: ";");
                        scanner.scanString("@end", into: nil)
                    }
                }
            }
        }
        scanner.charactersToBeSkipped = nil
    }

    private func analysisImplementation(_ str: NSString) {
        let scanner = Scanner(string: str as String)
        let implementationFlag = CharacterSet.init(charactersIn: "-+@(\n \t");
        while scanner.scanUpTo("@implementation", into: nil) {
            scanner.scanString("@implementation", into: nil)
            var classname : NSString?
            if !scanner.scanUpToCharacters(from: implementationFlag, into: &classname) {
                continue
            }
            var category : String? = nil
            var categoryRange = NSMakeRange(NSNotFound, 0)
            for index in scanner.scanLocation..<str.length {
                let ch = str.character(at: index)
                if ch == unichar.init(" ") || ch == unichar.init("\n") {
                    continue
                }
                if ch == unichar.init("(") {
                    categoryRange.location = index + 1
                } else if ch == unichar.init(")") {
                    categoryRange.length = index - categoryRange.location
                    category = str.substring(with: categoryRange)
                    category = category?.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)
                    break
                } else {
                    if categoryRange.location == NSNotFound {
                        break
                    }
                }
            }
            if let clazzName = classname as String?, let _category = category {
                var clazz : Class?
                if category?.characters.count == 0 {
                    clazz = self.clazzs[clazzName]
                } else {
                    let identifier = String.init(format: "%@ (%@)", clazzName, _category)
                    clazz = self.clazzs[identifier]
                }
                if clazz == nil {
                    print("Code exists error")
                    exit(-1)
                }
                let location_start = scanner.scanLocation
                scanner.scanUpTo("@end", into: nil)
                let classDescribeString = str.substring(with: NSMakeRange(location_start, scanner.scanLocation - location_start))
                self.analysisFileWithString(classDescribeString, into: clazz!, methodFlag: "{");
                scanner.scanString("@end", into: nil)
            }
        }
    }

    private func analysisFileWithString(_ fileString: String, into clazz: Class, methodFlag: String) {
        let scanner = Scanner.init(string: fileString)
        var string : NSString?

        let __scanTagString__ = "CO_CONFUSION_"
        let __method__ = "METHOD"
        let __property__ = "PROPERTY"

        while scanner.scanUpTo(__scanTagString__, into: &string), !scanner.isAtEnd {
            scanner.scanString(__scanTagString__, into: nil)
            string = nil
            scanner.scanUpToCharacters(from: NSCharacterSet.whitespacesAndNewlines, into: &string)
            if (string?.isEqual(to: __property__))! {
                var property : NSString?
                if scanner.scanUpTo(";", into: &property) {
                    if let prop = property as String? {
                        clazz.addProperty(Property.init(name: prop))
                    }
                }
            } else if (string?.isEqual(to: __method__))! {
                var method : NSString?
                if scanner.scanUpTo(methodFlag, into: &method), !scanner.isAtEnd {
                    if let _method = method as String? {
                        clazz.addMethod(Method.init(name: _method))
                        self.analysisMethodWithString(_method.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                                                      into: clazz.methods.last!)
                    }
                }
            }

        }
    }
    private func analysisMethodWithString(_ methodString: String, into method: Method) {
        let scanner = Scanner.init(string: methodString)
        scanner.scanUpTo("(", into: nil)
        scanner.scanLocation += 1
        scanner.charactersToBeSkipped = CharacterSet.whitespacesAndNewlines

        var selector : NSString?
        scanner.scanUpTo(":", into: &selector)
        if selector == nil {
            print("code exists error")
            exit(-1)
        }
        scanner.charactersToBeSkipped = nil
        method.selectors.append(Selector.init(name: selector! as String))

        // 找余下的selector
        while scanner.scanUpTo(")", into: nil), !scanner.isAtEnd {
            scanner.scanString(")", into: nil)
            scanner.charactersToBeSkipped = CharacterSet.whitespacesAndNewlines
            scanner.scanUpToCharacters(from: CharacterSet.whitespacesAndNewlines, into: nil)
            if scanner.scanUpTo(":", into: &selector), !scanner.isAtEnd {
                method.selectors.append(Selector.init(name: selector! as String))
            }
            scanner.charactersToBeSkipped = nil
        }
    }

    public mutating func write() {
        if self.outStream?.needGenerateObfuscationCode == false {
            return
        }
        self.outStream?.begin()
        for (_, obj) in clazzs {
            var dict = [String: String]()
            if let _ = obj.categoryname {
                dict[obj.categoryname!] = obj.fakename
            } else {
                dict[obj.classname] = obj.fakename
            }
            for prop in obj.properties {
                dict[prop.name] = prop.fakename
            }
            for method in obj.methods {
                for selector in method.selectors {
                    dict[selector.name] = selector.fakename
                }
            }
            self.outStream?.writeObfuscation(code: dict)
        }
        self.outStream?.end()
    }
}
