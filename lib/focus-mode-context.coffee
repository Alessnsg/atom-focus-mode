{CompositeDisposable} = require 'atom'
FocusModeBase = require './focus-mode-base'

class FocusContextMode extends FocusModeBase

    constructor: () ->
        super('FocusContextMode')
        @isActivated = false
        @focusContextMarkerCache = {}
        @editorFileTypeCache = {}
        @focusContextBodyClassName = "focus-mode-context"
        @configSubscriptions = null #@registerConfigSubscriptions()

    on: =>
        @isActivated = true
        textEditor = @getActiveTextEditor()
        cursor = textEditor.getLastCursor()
        @contextModeOnCursorMove(cursor)
        @addCssClass(@getBodyTagElement(), @focusContextBodyClassName)

    off: =>
        @isActivated = false
        @removeContextModeMarkers()
        @focusContextMarkerCache = {}
        @removeCssClass(@getBodyTagElement(), @focusContextBodyClassName)


    # isCoffeeScriptMethodSignature: (rowText) ->
    #     return /:\s*\(.*\)\s*(=>|->)/.test(rowText)
    #
    # isPythonMethodSignature: (rowText) ->
    #     return /\s*def\s*.*\s*\(.*\)\s*:/.test(rowText)

    isJavascriptFunctionSignature: (rowText) ->
        # return /^.*\s+function\s*([a-zA-Z0-9_-]*)?\s*\({1}.*\){1}\s*{\s*$/.test(rowText)
        return /^.*\s*function\s*([a-zA-Z0-9_-]*)?\s*\({1}.*\){1}\s*{\s*$/.test(rowText)


    lineIsClosingCurly: (lineText) ->
        console.log("line text = ", lineText, " is a clsoing curly = ", /^\s*}\s*$/.test(lineText))
        return /^\s*}\s*;?\s*$/.test(lineText)


    isMethodStartRow: (rowText, editor) =>
        fileType = @getFileTypeForEditor(editor)
        if(fileType is "coffee")
            return /:\s*\(.*\)\s*(=>|->)/.test(rowText)
        else if(fileType is "py")
            return /\s*def\s*.*\s*\(.*\)\s*:/.test(rowText)
        else if(fileType is "js")
            return @isJavascriptFunctionSignature(rowText)
        else
            console.log("isMethodStartRow FILE TYPE NOT MATCHED fileType = ", fileType)
            return false


    # Get method/function start line/buffer row
    getContextModeBufferStartRow: (cursorBufferRow, editor) =>
        matchedBufferRowNumber = 0 # default to first row in file
        rowIndex = cursorBufferRow

        while rowIndex >= 0
            rowText = editor.lineTextForBufferRow(rowIndex)
            console.log("rowIndex = ", rowIndex, " row text = ", rowText)
            if(@isMethodStartRow(rowText, editor))
                matchedBufferRowNumber = rowIndex
                console.log(">>>>>>>>was matched row = ", matchedBufferRowNumber)
                break
            else
                rowIndex = rowIndex - 1

        return matchedBufferRowNumber


    # Get method/function end line/buffer row
    getContextModeBufferEndRow: (methodStartRow, editor) =>
        bufferLineCount = editor.getLineCount()
        fileType = @getFileTypeForEditor(editor)
        matchedBufferRowNumber = bufferLineCount # default to last row in file
        rowIndex = methodStartRow
        startRowIndent = editor.indentationForBufferRow(methodStartRow)
        console.log("methodStartRow row indentation = ", startRowIndent)

        while rowIndex <= bufferLineCount
            rowIndex = rowIndex + 1
            rowText = editor.lineTextForBufferRow(rowIndex)

            if(fileType is "coffee" or fileType is "py")
                # finds end of method body by finding next method start or end of file, then moves back up 1 line
                if(@isMethodStartRow(rowText, editor) and editor.indentationForBufferRow(rowIndex) <= startRowIndent)
                    matchedBufferRowNumber = rowIndex # -1
                    break

            else if(fileType is "js")
                # finds a closing curly on same level of indentation as function/method start row
                if(editor.indentationForBufferRow(rowIndex) is startRowIndent and @lineIsClosingCurly(rowText))
                    matchedBufferRowNumber = rowIndex + 1 # +1 as buffer range end row isn't included in range and we also want it decorated
                    break


        console.log("getContextModeBufferEndRow fileType is ", fileType, " and matched row = ", matchedBufferRowNumber)

        # return editor.previousNonBlankRow(matchedBufferRowNumber)
        return matchedBufferRowNumber


    getContextModeBufferRange: (bufferPosition, editor) =>
        cursorBufferRow = bufferPosition.row
        console.log("current buffer row = ", cursorBufferRow)
        startRow = @getContextModeBufferStartRow(cursorBufferRow, editor)
        console.log("getContextModeBufferRange startRow = ", startRow)
        # startRowIndent = editor.indentationForBufferRow(startRow)
        # console.log("start row indentation = ", startRowIndent)
        endRow = @getContextModeBufferEndRow(startRow, editor)
        # endRow = @getContextModeBufferEndRow(cursorBufferRow, editor, startRowIndent)
        console.log("getContextModeBufferRange endRow = ", endRow)

        return [[startRow, 0], [endRow, 0]]


    createContextModeMarker: (textEditor) =>
        bufferPosition = textEditor.getCursorBufferPosition()
        contextBufferRange = @getContextModeBufferRange(bufferPosition, textEditor)
        marker = textEditor.markBufferRange(contextBufferRange)
        textEditor.decorateMarker(marker, type: 'line', class: @focusLineCssClass)

        return marker


    removeContextModeMarkers: =>
        for editor in @getAtomWorkspaceTextEditors()
            marker = @focusContextMarkerCache[editor.id]
            marker.destroy() if marker


    getContextModeMarkerForEditor: (editor) =>
        marker = @focusContextMarkerCache[editor.id]
        if not marker
            marker = @createContextModeMarker(editor)
            @focusContextMarkerCache[editor.id] = marker

        return marker


    getFileTypeForEditor: (editor) =>
        fileType = @editorFileTypeCache[editor.id]
        console.log("fileType for editor ", editor.id, " from cache = ", fileType)
        if not fileType
            splitFileName = editor.getTitle().split(".")
            fileType = if splitFileName.length > 1 then splitFileName[1] else ""
            @editorFileTypeCache[editor.id] = fileType
            console.log("fileType for editor ", editor.id, " not in cache, fileType = ", fileType)

        return fileType


    contextModeOnCursorMove: (cursor) =>
        editor = cursor.editor
        marker = @getContextModeMarkerForEditor(editor)
        fileType = @getFileTypeForEditor(editor)
        console.log("contextModeOnCursorMove fileType = ", fileType)
        bufferPosition = editor.getCursorBufferPosition()
        range = @getContextModeBufferRange(bufferPosition, editor)
        console.log("contextModeOnCursorMove range = ", range)
        startRow = range[0][0]
        endRow = range[1][0]
        console.log("startRow = ", startRow, " endRow = ", endRow)

        marker.setTailBufferPosition([startRow, 0])
        marker.setHeadBufferPosition([endRow, 0])


    dispose: =>
        @configSubscriptions.dispose() if @configSubscriptions


module.exports = FocusContextMode


# isMethodDecoration: (rowText) =>
#     return /\s*@\S*\s*/.test(rowText)
#
# if(@isMethodDecoration(editor.lineTextForBufferRow(rowIndex))) {
#     # As line is a decorator, iterate forward to find next line matching a method signature
#     return @getContextModeBufferEndRow(rowIndex, editor)
# }
