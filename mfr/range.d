
//  Range consumption primitives
//  Copyright (c) 2009-2010  Michel Fortin
//
//  Distributed under the Boost Software License, version 1.0.
//  See accompanying file.

/**
 * This module contains functions to abstract the consumption and retention of 
 * the consumed content of a range. Sliceable ranges will be taken a slice, 
 * others will just use Appender to accumulate the consumed content.
 * 
 * Copyright: 2009-2010, Michel Fortin
 */
module mfr.range;

import std.range;
import std.array;


E[] consume(alias until, R, E = ElementType!R)(ref R range) /*if (!isForwardRange!R)*/ {
	Appender!(E[]) result;
	while (!range.empty && until(range.front) == true) {
		result.put(range.front);
		range.popFront();
	}
	return result.data;
}

// -- Temporarily removed / http://d.puremagic.com/issues/show_bug.cgi?id=4345
//R consume(alias until, R, E = R)(ref R range) if (isForwardRange!R) {
//	auto savedRange = range.save();
//	while (!range.empty && until(range.front) == true) {
//		range.popFront();
//	}
//	return savedRange.take(savedRange.length-range.length);
//}

E[] consume(alias until, R : E[], E)(ref R range) {
	auto savedRange = range;
	while (!range.empty && until(range.front) == true) {
		range.popFront();
	}
	return savedRange[0..savedRange.length-range.length];
}

unittest {
	string test = "abcdef";
	string result = consume!((c){ return c < 'd'; })(test);
	assert(result == "abc");
	assert(test == "def");
}
unittest {
	wstring test = "abcdef";
	wstring result = consume!((c){ return c < 'd'; })(test);
	assert(result == "abc");
	assert(test == "def");
}
unittest {
	int[] test = [1,2,3,4,5,6];
	int[] result = consume!((c){ return c < 4; })(test);
	assert(result == [1,2,3]);
	assert(test == [4,5,6]);
}

version (unittest) import std.container;

unittest {
	auto container = SList!int(1,2,3,4,5,6);
	auto range = container[];
//	static assert(isForwardRange!(typeof(range)));
	int[] result = consume!((c){ return c < 4; })(range);
	assert(result == [1,2,3]);
	int[] array;
	foreach (value; range) array ~= value;
	assert(array == [4,5,6]);
}

version (none) unittest {
	auto container = Array!int(1,2,3,4,5,6);
	auto range = container[];
	static assert(isForwardRange!(typeof(range)));
//	int[] result = consume!((c){ return c < 4; })(range);
//	assert(result == [1,2,3]);
//	assert(array(range) == [4,5,6]);
}



E[] consumeEx(alias until, R, E = ElementType!R)(ref R range) /*if (!isForwardRange!R)*/ {
	Appender!(E[]) result;
	void next() {
		result.put(range.front);
		range.popFront();
	}
	while (!range.empty && until(range.front, next) == true) {}
	return result.data;
}

// -- Temporarily removed / http://d.puremagic.com/issues/show_bug.cgi?id=4345
//R consumeEx(alias until, R, E = R)(ref R range) if (isForwardRange!R) {
//	auto savedRange = range.save();
//	void next() {
//		range.popFront();
//	}
//	while (!range.empty && until(range.front, next) == true) {}
//	return savedRange.take(savedRange.length-range.length);
//}

E[] consumeEx(alias until, R : E[], E)(ref R range) {
	auto savedRange = range;
	typeof(range.front) next() {
		range.popFront();
		return range.front;
	}
	bool predicate() {
		static if (is(typeof(until(range.front, &next))))
			return until(range.front, &next) == true;
		else
			return until(range.front) == true;
	}
	while (!range.empty && predicate()) {
		next();
	}
	return savedRange[0..savedRange.length-range.length];
}

unittest {
	bool consumer(dchar c, dchar delegate() next) {
		if (c < 'd') { return true; }
		if (c == 'd') { next(); return false; } // take D but stop just after
		return false;
	}
	
	string test = "abcddef";
	string result = consumeEx!(consumer)(test);
	assert(result == "abcd");
	assert(test == "def");
}

