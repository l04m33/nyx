when not defined(nolog):
    import pure/logging
    var logger = newConsoleLogger()
    addHandler(logger)

    template setLogLevel*(level: Level) =
        logger.levelThreshold = level

    export debug, info, warn, error, fatal
    export Level

else:
    from pure/logging import Level

    template setLogLevel*(level: Level) =
        discard

    template debug*(frmt: string, args: varargs[string, `$`]) =
        discard

    template info*(frmt: string, args: varargs[string, `$`]) =
        discard

    template warn*(frmt: string, args: varargs[string, `$`]) =
        discard

    template error*(frmt: string, args: varargs[string, `$`]) =
        discard

    template fatal*(frmt: string, args: varargs[string, `$`]) =
        discard

    export Level
