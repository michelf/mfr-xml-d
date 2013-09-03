
//  Range by-unit primitives
//  Copyright (c) 2009-2010  Michel Fortin
//
//  Distributed under the Boost Software License, version 1.0.
//  See accompanying file.

/**
 * This module contains primitives to advance by one code unit instead of one
 * code point in arrays. This is useful when you just want to check if the 
 * next character is the ASCII character you expect, since it avoids decoding
 * unnecessarily a UTF-8 multi-byte sequence at each check.
 * 
 * Copyright: 2009-2010, Michel Fortin
 */
module mfr.byunit;

import mfr.range;

import std.range : empty;


char frontUnit(string input) {
	assert(input.length > 0);
	return input[0];
}
wchar frontUnit(wstring input) {
	assert(input.length > 0);
	return input[0];
}
dchar frontUnit(dstring input) {
	assert(input.length > 0);
	return input[0];
}

void popFrontUnit(ref string input) {
	assert(input.length > 0);
	input = input[1..$];
}
void popFrontUnit(ref wstring input) {
	assert(input.length > 0);
	input = input[1..$];
}
void popFrontUnit(ref dstring input) {
	assert(input.length > 0);
	input = input[1..$];
}

version (unittest) {
	import std.string : front, popFront;
}

unittest {
	string test = "été";
	assert(test.length == 5);
	
	string test2 = test;
	assert(test2.front == 'é');
	test2.popFront();
	assert(test2.length == 3); // removed "é" which is two UTF-8 code units
	
	string test3 = test;
	assert(test3.frontUnit == "é"c[0]);
	test3.popFrontUnit();
	assert(test3.length == 4); // removed first half of "é" which, one UTF-8 code units
}


E[] consumeUnit(alias until, R : E[], E)(ref R range) {
	auto savedRange = range;
	while (!range.empty && until(range.frontUnit) == true) {
		range.popFrontUnit();
	}
	return savedRange[0..savedRange.length-range.length];
}

auto consumeUnit(alias until, R, A...)(ref R range) {
	return consume!(until, R, A)(range);
}

unittest {
	string test = "été";
	assert(test.length == 5);
	
	string test2 = test;
	assert(consume!((c){ return c > 128; })(test2) == "é");
	assert(test2.length == 3); // removed "é" which is two UTF-8 code units

	string test3 = test;
	assert(consumeUnit!((c){ return c == "é"c[0]; })(test3) == ["é"c[0]]);
	assert(test3.length == 4); // removed first half of "é" which, one UTF-8 code units
}

