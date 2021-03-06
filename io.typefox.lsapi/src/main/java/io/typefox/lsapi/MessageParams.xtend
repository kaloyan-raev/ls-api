/*******************************************************************************
 * Copyright (c) 2016 TypeFox GmbH (http://www.typefox.io) and others.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *******************************************************************************/
package io.typefox.lsapi

import io.typefox.lsapi.annotations.LanguageServerAPI

/**
 * The show message notification is sent from a server to a client to ask the client to display a particular message
 * in the user interface.
 * 
 * The log message notification is send from the server to the client to ask the client to log a particular message.
 */
@LanguageServerAPI
interface MessageParams {
	
	/**
	 * The message type.
	 */
	def MessageType getType()
	
	/**
	 * The actual message.
	 */
	def String getMessage()
	
}