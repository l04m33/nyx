import 
    mimetypes,
    strutils


let mimeDb = newMimetypes()


const defaultType = ""


proc getMimetype*(path: string): string =
    var lastDot = path.rfind('.')
    var lastSlash = path.rfind('/')

    if lastDot <= lastSlash:
        return defaultType
    else:
        var ext = path[(lastDot+1)..(path.len())]
        return mimeDb.getMimetype(ext, defaultType)
