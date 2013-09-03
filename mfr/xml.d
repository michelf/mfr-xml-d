
//  XML Tree Model
//  Copyright (c) 2009-2010  Michel Fortin
//
//  Distributed under the Boost Software License, version 1.0.
//  See accompanying file.

/**
 * This XML API contains an object model to manipulate XML trees.
 * 
 * Copyright: 2009-2010, Michel Fortin
 */
module mfr.xml;

import mfr.xmltok;

import std.string : icmp;


/**
 * Base class for all nodes of the XML document model.
 */
abstract class Node
{
	/**
	 * Write document to the specified XML token writer.
	 */
	abstract void writeTo(Writer writer);
	
	/**
	 * Convert node to XML string form. This function uses writeTo to create
	 * the XML form.
	 */
	final string toXML()
	{
		return writeToString((Writer writer) { writeTo(writer); });
	}
}

/**
 * Document object at root of the XML document model.
 *
 * Example:
---
auto doc = new Document;
doc.read("<hello>world</hello>");
---
 */
class Document
{
	/** The document's root element. */
	Element root;
	
	/** List of nodes at the root of the document. */
	Node[] nodes;
	
	private string input;
	
	/**
	 * Read the document from the given XML byte input. This will check for
	 * a byte order mask, then parse the document with the right character set.
	 *
	 * Note: Only UTF-8 is supported at the moment.
	 *
	 * Params:
	 *  input = ubyte input to read the document from.
	 *
	 * Throws: at any well-formness error. The document will contain the tree
	 * that was built up to the error point.
	 *
	 * Note: read will replace any existing content in the document.
	 */
	void read(immutable(ubyte)[] input)
	{
		auto enc = readBOM(input);
		
		switch (enc)
		{
		case XmlEncoding.UTF8, XmlEncoding.UNKNOWN:
			read(cast(string)input);
			break;
		default:
			throw new Exception("XML parser only supports UTF-8.");
		}
	}

	/**
	 * Read the document from the given XML character input.
	 *
	 * Params:
	 *  input = character input to read the document from.
	 *
	 * Throws: at any well-formness error. The document will contain the tree
	 * that was built up to the error point.
	 *
	 * Note: read will replace any existing content in the document.
	 */
	void read(string input)
	{
		root = null;
		nodes.length = 0;
		
		XMLDecl decl;
		if (readXMLDecl(input, decl))
		{
			if (!decl.encName.empty)
				if (icmp(decl.encName, "UTF-8") != 0)
					throw new Exception("XML parser only supports UTF-8 encoding.");
			if (decl.versionNum != "1.0" && decl.versionNum != "1.1")
				throw new Exception("Unknown XML version '" ~ decl.versionNum ~ "'.");
		}
		
		scope parser = new class
		{
			ParsingState state;
			
			bool read()
			{
				return tokenize!(opCall, state)(input);
			}

			void opCall(CharDataToken token)
			{
				// Ignore
				// TODO: Check for whitespace?
			}
			void opCall(OpenElementToken token)
			{
				if (root is null)
				{
					root = new Element(this.outer, token.name);
					nodes ~= root;
					root.read(input, state);
				}
				else
					throw new Exception("Can only have one element at root of document.");
			}
			void opCall(CloseElementToken token)
			{
				if (root && token.name == root.name)
					assert(false, "Closing tag should be handled by element.");
				else
					throw new Exception("Found unexpected closing tag "
						"'" ~ token.name ~ "' at document root.");
			}
			void opCall(PIToken token)
			{
				nodes ~= new PI(token.target, token.content);
			}
			void opCall(CommentToken token)
			{
				nodes ~= new Comment(token.content);
			}
			void opCall(AttrToken token)
			{
				assert(0, "Unexpected " ~ typeof(token).stringof ~ " at document root.");
			}
			void opCall(OpenTagDoneToken token)
			{
				assert(0, "Unexpected " ~ typeof(token).stringof ~ " at document root.");
			}
			void opCall(EmptyOpenTagDoneToken token)
			{
				assert(0, "Unexpected " ~ typeof(token).stringof ~ " at document root.");
			}
			void opCall(CDataSectionToken token)
			{
				throw new Exception("Unexpected CDATA section (at document root).");
			}
			void opCall(EntityReferenceToken token)
			{
				throw new Exception("Found unsupported entity reference '" ~ 
					token.entityName ~ "'.");
			}
		};
		
		parser.read();
	}
	
	/**
	 * Write document to the specified XML token writer.
	 */
	void writeTo(Writer writer)
	{
		if (nodes.length > 0)
			nodes[0].writeTo(writer);
		if (nodes.length > 1)
		{
			CharDataToken newline = { "\n" };
			foreach (node; nodes[1..$])
			{
				writer(newline);
				node.writeTo(writer);
			}
		}
	}
	
	/**
	 * Convert document to XML string form. This function uses writeTo to
	 * create the XML form.
	 */
	final string toXML()
	{
		return writeToString((Writer writer) { writeTo(writer); });
	}
}


/**
 * Element node for the XML document model.
 */
class Element : Node
{
	/** Document this element belongs to. */
	Document document;
	/** Name of this element. */
	string name;
	/** Attributes of this element. */
	string[string] attr;
	/** Content of this elements. */
	Node[] nodes;
	
	/**
	 * Create a new Element with the given name.
	 *
	 * Params:
	 *  document = the document this elements fits in.
	 *  name = the name of this element.
	 */
	this(Document document, string name)
	{
		this.document = document;
		this.name = name;
	}
	
	private void read(ref string input, ref ParsingState state)
	{
		scope parser = new class
		{
			ParsingState state;
			
			bool read()
			{
				return tokenize!(opCall, state)(input);
			}
		
			void opCall(AttrToken token)
			{
				attr[token.name] = token.value;
			}
			void opCall(CharDataToken token)
			{
				nodes ~= new Text(token.data);
			}
			void opCall(CDataSectionToken token)
			{
				nodes ~= new Text(token.content);
			}
			void opCall(OpenElementToken token)
			{
				auto element = new Element(document, token.name);
				nodes ~= element;
				element.read(input, state);
			}
			bool opCall(CloseElementToken token)
			{
				if (token.name == name)
					return true;
				else
					throw new Exception("Found unmatched closing tag "
						"'" ~ token.name ~ "' (inside '" ~ name ~ "').");
			}
			void opCall(OpenTagDoneToken token)
			{
			}
			bool opCall(EmptyOpenTagDoneToken token)
			{
				return true;
			}
			void opCall(PIToken token)
			{
				nodes ~= new PI(token.target, token.content);
			}
			void opCall(CommentToken token)
			{
				nodes ~= new Comment(token.content);
			}
			void opCall(EntityReferenceToken token)
			{
				throw new Exception("Found unsupported entity reference '" ~ 
					token.entityName ~ "'.");
			}
		};
		
		parser.state = state;
		parser.read();
		state = parser.state;
	}
	
	void writeTo(Writer writer)
	{
		OpenElementToken open;
		open.name = name;
		writer(open);
		
		foreach (key, value; attr)
		{
			AttrToken attrToken;
			attrToken.name = key;
			attrToken.value = value;
			writer(attrToken);
		}
		
		if (nodes.empty)
		{
			EmptyOpenTagDoneToken done;
			writer(done);
		}
		else
		{
			OpenTagDoneToken done;
			writer(done);
			
			foreach (node; nodes)
				node.writeTo(writer);
			
			CloseElementToken close;
			close.name = name;
			writer(close);
		}
	}
}

/**
 * Processing instruction node for the XML document model.
 */
class PI : Node
{
	/** Target processor of this PI. */
	string target;
	/** Content of this PI. */
	string content;
	
	/**
	 * Create a new PI for the given target and content.
	 *
	 * Params:
	 *  target = name of the target processor
	 *  content = content of this processor instruction
	 */
	this(string target, string content)
	{
		this.target = target;
		this.content = content;
	}
	
	void writeTo(Writer writer)
	{
		PIToken pi;
		pi.target = target;
		pi.content = content;
		writer(pi);
	}
}

/**
 * Comment node for the XML document model.
 */
class Comment : Node
{
	/** Content of this comment. */
	string content;
	
	/**
	 * Create a new Comment with the given content.
	 *
	 * Params:
	 *  content = textual content of this comment.
	 */
	this(string content)
	{
		this.content = content;
	}
	
	void writeTo(Writer writer)
	{
		CommentToken comment;
		comment.content = content;
		writer(comment);
	}
}

/**
 * Represents a run of text. CDATA sections are not treated differently than 
 * normal text. Text objects may be adjacent to other Text objects.
 */
class Text : Node
{
	/** Content of this text node. */
	string content;
	
	/**
	 * Create a new Text with the given content.
	 *
	 * Params:
	 *  content = textual content of this text node.
	 */
	this(string content)
	{
		this.content = content;
	}
	
	void writeTo(Writer writer)
	{
		CharDataToken cdata;
		cdata.data = content;
		writer(cdata);
	}
}

import std.stdio;

unittest
{
	// Creating object model from XML
	string xml =
		"<root><message a='b'>x <message test=\"world\">hello<br/></message> x</message>"
		"<?is  content king??><!-- this is - a comment --><![CDATA[[cdata]]]></root>";

	auto doc = new Document;
	doc.read(xml);
	
	assert(doc.root.name == "root");
	assert(doc.root.nodes.length > 0);
	{
		Element element = cast(Element)doc.root.nodes[0];
		assert(element);
		assert(element.name == "message");
		assert("a" in element.attr);
		assert(element.attr["a"] == "b");
		
		assert(element.nodes.length > 0);
		{
			Text text = cast(Text)element.nodes[0];
			assert(text);
			assert(text.content == "x ");
		}
		
		assert(element.nodes.length > 1);
		{
			Element subelement = cast(Element)element.nodes[1];
			assert(subelement);
			assert(subelement.name == "message");
			assert("test" in subelement.attr);
			assert(subelement.attr["test"] == "world");
			
			assert(subelement.nodes.length > 0);
			{
				Text hello = cast(Text)subelement.nodes[0];
				assert(hello);
				assert(hello.content == "hello");
			}
			
			assert(subelement.nodes.length > 1);
			{
				Element br = cast(Element)subelement.nodes[1];
				assert(br);
				assert(br.name == "br");
				assert(br.nodes.length == 0);
			}
			
			assert(subelement.nodes.length == 2);
		}
		
		assert(element.nodes.length > 2);
		{
			Text text = cast(Text)element.nodes[2];
			assert(text);
			assert(text.content == " x");
		}
		
		assert(element.nodes.length == 3);
	}
	
	assert(doc.root.nodes.length > 1);
	{
		PI pi = cast(PI)doc.root.nodes[1];
		assert(pi);
		assert(pi.target == "is");
		assert(pi.content == "content king?");
	}
	
	assert(doc.root.nodes.length > 2);
	{
		Comment comment = cast(Comment)doc.root.nodes[2];
		assert(comment);
		assert(comment.content == " this is - a comment ");
	}
	
	assert(doc.root.nodes.length > 3);
	{
		Text text = cast(Text)doc.root.nodes[3];
		assert(text);
		assert(text.content == "[cdata]");
	}
	
	assert(doc.root.nodes.length == 4);
}


unittest
{
	// Serializing object model to canonical XML.
	// Creating object model from XML
	const sourceXml =
		`<?xml version='1.0'?>`"\n"
		`<?xml-stylesheet   href="doc.xsl`"\n"
		`  type='text/xsl'   ?>`"\n"
		"\n\n"
		`<!DOCTYPE doc SYSTEM "doc.dtd">`"\n"
		"\n"
		`<doc   a = 'o'>Hello&#44; world&#x21;<br /><!-- Comment 1 --></doc>`"\n"
		`<?pi-without-data     ?>`"\n"
		`<!-- Comment 2 -->`"\n";
	const outputXml =
		`<?xml-stylesheet href="doc.xsl`"\n"
		`  type='text/xsl'   ?>`"\n"
		`<doc a="o">Hello, world!<br/><!-- Comment 1 --></doc>`"\n"
		`<?pi-without-data?>`"\n"
		`<!-- Comment 2 -->`;
	
	auto doc = new Document;
	doc.read(sourceXml);
	assert(doc.toXML() == outputXml);
}


/**
 Extract textual content from a node and all its children.
 */
string textContent(Node node) {
	return textContent([node]);
}

string textContent(Element element) {
	return textContent(element.nodes);
}

string textContent(Node[] nodes)
{
	struct StringOutput
	{
		string output;
		
		void write(string s)
		{
			output ~= s;
		}
	}
	
	StringOutput strout;
	auto writer = new XMLWriter!strout;
	foreach (node; nodes)
		node.writeTo(writer);
	return strout.output;
}
