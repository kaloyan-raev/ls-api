/*******************************************************************************
 * Copyright (c) 2016 TypeFox GmbH (http://www.typefox.io) and others.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *******************************************************************************/
package io.typefox.lsapi.json

import io.typefox.lsapi.CodeActionParams
import io.typefox.lsapi.CodeLens
import io.typefox.lsapi.CodeLensParams
import io.typefox.lsapi.CompletionItem
import io.typefox.lsapi.DidChangeConfigurationParams
import io.typefox.lsapi.DidChangeTextDocumentParams
import io.typefox.lsapi.DidChangeWatchedFilesParams
import io.typefox.lsapi.DidCloseTextDocumentParams
import io.typefox.lsapi.DidOpenTextDocumentParams
import io.typefox.lsapi.DidSaveTextDocumentParams
import io.typefox.lsapi.DocumentFormattingParams
import io.typefox.lsapi.DocumentOnTypeFormattingParams
import io.typefox.lsapi.DocumentRangeFormattingParams
import io.typefox.lsapi.DocumentSymbolParams
import io.typefox.lsapi.InitializeParams
import io.typefox.lsapi.LanguageServer
import io.typefox.lsapi.Message
import io.typefox.lsapi.MessageAcceptor
import io.typefox.lsapi.NotificationMessage
import io.typefox.lsapi.NotificationMessageImpl
import io.typefox.lsapi.ReferenceParams
import io.typefox.lsapi.RenameParams
import io.typefox.lsapi.RequestMessage
import io.typefox.lsapi.ResponseError
import io.typefox.lsapi.ResponseErrorImpl
import io.typefox.lsapi.ResponseMessageImpl
import io.typefox.lsapi.TextDocumentPositionParams
import io.typefox.lsapi.WorkspaceSymbolParams
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.Executors
import java.util.concurrent.Future
import org.eclipse.xtend.lib.annotations.Accessors

/**
 * Wraps a language server implementation and adapts it to the JSON-based protocol.
 */
class LanguageServerToJsonAdapter implements MessageAcceptor {
	
	@Accessors(PROTECTED_GETTER)
	val LanguageServer delegate
	
	@Accessors(PROTECTED_GETTER)
	val LanguageServerProtocol.InputListener inputListener
	
	@Accessors
	val LanguageServerProtocol protocol
	
	val executorService = Executors.newCachedThreadPool
	
	Future<?> inputListenerJoin
	
	
	new(LanguageServer delegate) {
		this(delegate, new MessageJsonHandler)
	}
	
	new(LanguageServer delegate, MessageJsonHandler jsonHandler) {
		this.delegate = delegate
		protocol = new LanguageServerProtocol(jsonHandler, this)
		inputListener = new LanguageServerProtocol.InputListener(protocol)
		delegate.textDocumentService.onPublishDiagnostics[
			sendNotification(MessageMethods.SHOW_DIAGNOSTICS, it)
		]
		delegate.windowService.onLogMessage[
			sendNotification(MessageMethods.LOG_MESSAGE, it)
		]
		delegate.windowService.onShowMessage[
			sendNotification(MessageMethods.SHOW_MESSAGE, it)
		]
		delegate.windowService.onShowMessageRequest[
			sendNotification(MessageMethods.SHOW_MESSAGE_REQUEST, it)
		]
	}
	
	def void connect(InputStream input, OutputStream output) {
		if (isActive)
			throw new IllegalStateException("Cannot connect while the adapter is active.")
		protocol.output = output
		inputListener.input = input
	}
	
	def synchronized void start() {
		if (isActive)
			throw new IllegalStateException("Cannot start while the adapter is active.")
		inputListenerJoin = executorService.submit(inputListener)
	}
	
	def boolean isActive() {
		inputListener.isActive
	}
	
	def void join() {
		if (inputListenerJoin === null)
			throw new IllegalStateException("Cannot join before the adapter has been started.")
		inputListenerJoin.get()
	}
	
	def synchronized void stop() {
		inputListener.stop()
		delegate.shutdown()
	}
	
	override accept(Message message) {
		doAccept(message)
	}
	
	protected def dispatch doAccept(RequestMessage message) {
		var doStop = false
		try {
			val result = switch message.method {
				case MessageMethods.INITIALIZE:
					delegate.initialize(message.params as InitializeParams)
				case MessageMethods.DOC_COMPLETION:
					delegate.textDocumentService.completion(message.params as TextDocumentPositionParams)
				case MessageMethods.RESOLVE_COMPLETION:
					delegate.textDocumentService.resolveCompletionItem(message.params as CompletionItem)
				case MessageMethods.DOC_HOVER:
					delegate.textDocumentService.hover(message.params as TextDocumentPositionParams)
				case MessageMethods.DOC_SIGNATURE_HELP:
					delegate.textDocumentService.signatureHelp(message.params as TextDocumentPositionParams)
				case MessageMethods.DOC_DEFINITION:
					delegate.textDocumentService.definition(message.params as TextDocumentPositionParams)
				case MessageMethods.DOC_HIGHLIGHT:
					delegate.textDocumentService.documentHighlight(message.params as TextDocumentPositionParams)
				case MessageMethods.DOC_REFERENCES:
					delegate.textDocumentService.references(message.params as ReferenceParams)
				case MessageMethods.DOC_SYMBOL:
					delegate.textDocumentService.documentSymbol(message.params as DocumentSymbolParams)
				case MessageMethods.DOC_CODE_ACTION:
					delegate.textDocumentService.codeAction(message.params as CodeActionParams)
				case MessageMethods.DOC_CODE_LENS:
					delegate.textDocumentService.codeLens(message.params as CodeLensParams)
				case MessageMethods.RESOLVE_CODE_LENS:
					delegate.textDocumentService.resolveCodeLens(message.params as CodeLens)
				case MessageMethods.DOC_FORMATTING:
					delegate.textDocumentService.formatting(message.params as DocumentFormattingParams)
				case MessageMethods.DOC_RANGE_FORMATTING:
					delegate.textDocumentService.rangeFormatting(message.params as DocumentRangeFormattingParams)
				case MessageMethods.DOC_TYPE_FORMATTING:
					delegate.textDocumentService.onTypeFormatting(message.params as DocumentOnTypeFormattingParams)
				case MessageMethods.DOC_RENAME:
					delegate.textDocumentService.rename(message.params as RenameParams)
				case MessageMethods.WORKSPACE_SYMBOL:
					delegate.workspaceService.symbol(message.params as WorkspaceSymbolParams)
				case MessageMethods.SHUTDOWN: {
					delegate.shutdown()
					doStop = true
					null
				}
				case MessageMethods.EXIT: {
					delegate.exit()
					doStop = true
					null
				}
				default: {
					sendResponseError(message.id, "Invalid method: " + message.method, ResponseError.METHOD_NOT_FOUND)
					null
				}
			}
			if (result !== null)
				sendResponse(message.id, result)
		} catch (InvalidMessageException e) {
			sendResponseError(message.id, e.message, e.errorCode)
		} catch (Exception e) {
			sendResponseError(message.id, e.message, ResponseError.INTERNAL_ERROR)
		} finally {
			if (doStop)
				inputListener.stop()
		}
	}
	
	protected def dispatch doAccept(NotificationMessage message) {
		try {
			switch message.method {
				case MessageMethods.DID_OPEN_DOC:
					delegate.textDocumentService.didOpen(message.params as DidOpenTextDocumentParams)
				case MessageMethods.DID_CHANGE_DOC:
					delegate.textDocumentService.didChange(message.params as DidChangeTextDocumentParams)
				case MessageMethods.DID_CLOSE_DOC:
					delegate.textDocumentService.didClose(message.params as DidCloseTextDocumentParams)
				case MessageMethods.DID_SAVE_DOC:
					delegate.textDocumentService.didSave(message.params as DidSaveTextDocumentParams)
				case MessageMethods.DID_CHANGE_CONF:
					delegate.workspaceService.didChangeConfiguraton(message.params as DidChangeConfigurationParams)
				case MessageMethods.DID_CHANGE_FILES:
					delegate.workspaceService.didChangeWatchedFiles(message.params as DidChangeWatchedFilesParams)
			}
		} catch (Exception e) {
			protocol.logError(e)
		}
	}
	
	protected def sendNotification(String methodId, Object parameter) {
		val message = new NotificationMessageImpl => [
			jsonrpc = LanguageServerProtocol.JSONRPC_VERSION
			method = methodId
			params = parameter
		]
		protocol.accept(message)
	}
	
	protected def sendResponse(String responseId, Object resultValue) {
		val message = new ResponseMessageImpl => [
			jsonrpc = LanguageServerProtocol.JSONRPC_VERSION
			id = responseId
			result = resultValue
		]
		protocol.accept(message)
	}
	
	protected def sendResponseError(String responseId, String errorMessage, int errorCode) {
		sendResponseError(responseId, errorMessage, errorCode, null)
	}
	
	protected def sendResponseError(String responseId, String errorMessage, int errorCode, Object errorData) {
		val message = new ResponseMessageImpl => [
			jsonrpc = LanguageServerProtocol.JSONRPC_VERSION
			id = responseId
			error = new ResponseErrorImpl => [
				message = errorMessage
				code = errorCode
				data = errorData
			]
		]
		protocol.accept(message)
	}
	
}