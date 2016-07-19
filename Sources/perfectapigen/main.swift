
import Darwin
import PerfectLib
import PerfectMustache

var sourcesRoot: String?
var templateFile: String?
var destinationFile: String?

var args = Process.arguments

@noreturn
func usage() {
	print("Usage: \(Process.arguments.first!) [--root sources_root] [--template mustache_template] [--dest destination_file]")
	exit(0)
}

func argFirst() -> String {
	guard let frst = args.first else {
		print("Argument requires value.")
		exit(-1)
	}
	return frst
}

let validArgs = [
	"--root": {
		args.removeFirst()
		sourcesRoot = argFirst()
	},
	"--dest": {
		args.removeFirst()
		destinationFile = argFirst()
	},
	"--template": {
		args.removeFirst()
		templateFile = argFirst()
	},
	"--help": {
		usage()
	}]

while args.count > 0 {
	if let closure = validArgs[args.first!.lowercased()] {
		closure()
	}
	args.removeFirst()
}

guard let srcs = sourcesRoot else {
	usage()
}

struct ProcError: ErrorProtocol {
	let code: Int
	let msg: String?
}

func runProc(cmd: String, args: [String], read: Bool = false) throws -> String? {
	let envs = [("PATH", "/Users/kjessup/.swiftenv/shims:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"), ("HOME", "/Users/kjessup")]
	let proc = try SysProcess(cmd, args: args, env: envs)
	var ret: String?
	if read {
		var ary = [UInt8]()
		while true {
			do {
				guard let s = try proc.stdout?.readSomeBytes(count: 1024) where s.count > 0 else {
					break
				}
				ary.append(contentsOf: s)
			} catch PerfectLib.PerfectError.fileError(let code, _) {
				if code != EINTR {
					break
				}
			}
		}
		ret = UTF8Encoding.encode(bytes: ary)
	}
	let res = try proc.wait(hang: true)
	if res != 0 {
		let s = try proc.stderr?.readString()
		throw ProcError(code: Int(res), msg: s)
	}
	return ret
}

let repoList = ["Perfect-CURL/":"PerfectCURL",
                "Perfect-FastCGI/":"PerfectFastCGI",
                "Perfect-HTTP/":"PerfectHTTP",
                "Perfect-HTTPServer/":"PerfectHTTPServer",
                "Perfect-MongoDB/":"MongoDB",
                "Perfect-Mustache/":"PerfectMustache",
                "Perfect-MySQL/":"MySQL",
                "Perfect-Net/":"PerfectNet",
                "Perfect-Notifications/":"PerfectNotifications",
                "Perfect-PostgreSQL/":"PostgreSQL",
                "Perfect-Redis/":"PerfectRedis",
                "Perfect-SQLite/":"SQLite",
                "Perfect-Thread/":"PerfectThread",
                "Perfect-WebSockets/":"PerfectWebSockets",
                "PerfectLib/":"PerfectLib"
]

let workingDir = Dir.workingDir

func processAPISubstructure(_ substructures: [Any]) -> [[String:Any]]? {
	
	func cleanKey(_ key: String) -> String {
		if key.hasPrefix("key.") {
			return key[key.index(key.startIndex, offsetBy: 4)..<key.endIndex]
		}
		return key
	}
	
	func getType(_ value: String) -> String {
		switch value {
		case "source.lang.swift.decl.var.instance":
			return "var"
		case "source.lang.swift.decl.var.static":
			return "static var"
		case "source.lang.swift.decl.var.global":
			return "global var"
		case "source.lang.swift.decl.var.parameter":
			return "var parameter"
		case "source.lang.swift.decl.class":
			return "class"
		case "source.lang.swift.decl.struct":
			return "struct"
		case "source.lang.swift.decl.typealias":
			return "typealias"
		case "source.lang.swift.decl.protocol":
			return "protocol"
		case "source.lang.swift.decl.extension":
			return "extension"
		case "source.lang.swift.decl.function.method.instance":
			return "method"
		case "source.lang.swift.decl.function.method.static":
			return "static method"
		case "source.lang.swift.decl.function.free":
			return "function"
		case "source.lang.swift.decl.enum":
			return "enum"
		case "source.lang.swift.decl.enumcase": // filtered out
			return "enum case"
		case "source.lang.swift.decl.enumelement":
			return "case"
		default:
			fatalError("Unknown type \(value)")
		}
	}
	
	var retAry = [[String:Any]]()
	top:
	for substructure in substructures {
		guard let substructure = substructure as? [String:Any] else {
			continue
		}
		var subDict = [String:Any]()
		var wasInternal = false
		var wasEnumElement = false
		var wasEnumCase = false
		var subSubstructure: [Any]?
		
		for (key, value) in substructure {
			let key = cleanKey(key)
			switch key {
			case "accessibility":
				if let value = value as? String {
					guard value == "source.lang.swift.accessibility.public" || value == "source.lang.swift.accessibility.internal" else {
						continue top
					}
					wasInternal = value == "source.lang.swift.accessibility.internal"
				}
			case "doc.name", "name", "doc.comment",
			     "parsed_declaration", "typename":
				subDict[key] = value
			case "kind":
				if let value = value as? String {
					subDict[key] = getType(value)
					wasEnumElement = value == "source.lang.swift.decl.enumelement"
					wasEnumCase = value == "source.lang.swift.decl.enumcase"
				}
			case "substructure":
				subSubstructure = value as? [Any]
			default:
				()
			}
		}
		guard !wasInternal || wasEnumElement else {
			continue
		}
		guard subDict.count > 0 else {
			continue
		}
		if let subSubstructure = subSubstructure, ss = processAPISubstructure(subSubstructure) {
			if wasEnumCase {
				retAry.append(contentsOf: ss)
				continue
			} else {
				subDict["substructure"] = ss
			}
		} else if let kind = subDict["kind"] as? String where kind == "extension" {
			continue
		} else {
			subDict["substructure"] = [[String:Any]]()
		}
		retAry.append(subDict)
	}
	guard retAry.count > 0 else {
		return nil
	}
	return retAry
}

func processAPIInfo(projectName: String, apiInfo: [Any]) -> [[String:Any]] {
	var projectsList = [[String:Any]]()
	for subDict in apiInfo {
		guard let subDict = subDict as? [String:Any] else {
			continue
		}
		for (file, v) in subDict {
			guard let v = v as? [String:Any] else {
				continue
			}
			guard let substructure = v["key.substructure"] as? [Any] else {
				continue
			}
			if let sub = processAPISubstructure(substructure) {
				var projDict = [String:Any]()
				projDict["file"] = file
				projDict["substructure"] = sub
				projectsList.append(projDict)
			}
		}
	}
	return projectsList
}

func fixProjectName(_ name: String) -> String {
	if name[name.index(before: name.endIndex)] == "/" {
		return name[name.startIndex..<name.index(before: name.endIndex)]
	}
	return name
}

var projectsAry = [[String:Any]]()
let srcsDir = Dir(srcs)
try srcsDir.forEachEntry {
	name in
	
	guard let target = repoList[name] else {
		return
	}
	
	let repoDirPath = srcs + "/" + name
	let repoDir = Dir(repoDirPath)
	try repoDir.setAsWorkingDir()
		
	let sourcekitten = "/usr/local/bin/sourcekitten"
	let skArgs = ["doc", "--spm-module", target]
	
	let swift = "swift"
	let spmCleanArgs = ["build", "--clean=dist"]
	let spmBuildArgs = ["build"]
	
	let git = "git"
	let gitPullArgs = ["pull"]
	
	_ = try runProc(cmd: git, args: gitPullArgs)
//	_ = try runProc(cmd: swift, args: spmCleanArgs)
	_ = try runProc(cmd: swift, args: spmBuildArgs)
	let apiInfo = try runProc(cmd: sourcekitten, args: skArgs, read: true)
	let decodedApiInfo = try apiInfo?.jsonDecode() as? [Any]
	
	let projectAPI = processAPIInfo(projectName: name, apiInfo: decodedApiInfo!)
	var projectInfo = [String:Any]()
	projectInfo["name"] = fixProjectName(name)
	projectInfo["files"] = projectAPI
	projectsAry.append(projectInfo)
}

let resDict: [String:Any] = ["projects":projectsAry]

try workingDir.setAsWorkingDir()

var resultText: String?

if let template = templateFile {
	let context = MustacheEvaluationContext(templatePath: template, map: resDict)
	let collector = MustacheEvaluationOutputCollector()
	resultText = try context.formulateResponse(withCollector: collector)
} else { // write out json
	resultText = try resDict.jsonEncodedString()
}

let f: File?
if let dest = destinationFile {
	f = File(dest)
	try f?.open(.truncate)
} else {
	f = fileStdout
}
try f?.write(string: resultText!)
