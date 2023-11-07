module rcstring2;

version(unittest) {
	import std.format;
}

import core.memory : GC;

/** String is a reference counted, small string optimized string library.

D's in-build string type is one of its biggest strengths, but intensive use
can put a lot of pressure on the garbage collector and ultimately slow
programs down.

This library and its String type tries to address this.

The String type stores strings with up to and including 56 char's in a static
array.
This is what is called a small string optimization.
The idea here is that most strings handled by programs are comparatively
small.
The size is chosen such one String instance fits into the most common Level 1
CPU cache size of 64 bytes.

If the stored data exceeds 56 char's the String type will allocate storage on
the heap and deallocate it when the last reference to it goes out of scope.

As D offers much flexibility there will always be memory safety holes.
That being said, that one of the design goals of this String type to not have
footguns when the user uses the type sensible.

The gist of it is. DO NOT TAKE THE ADDRESS OF String OR ANY OF IT MEMBERS OR
RETURNED VALUES.

If you stick to this, you should be fine.

String pretends to be @safe, it is not!
The way things are, it has to pretend to be to be usable in quote on quote
normal D code.
Again, to not use the unary ampersand & operator to get the address of data
linked to a String instance.

The String type does generally not work at compile time (CT), as manual memory
management is not really a thing at CT.
*/

/// ditto
unittest {
	//
	// Normal String usage
	//
	String s = "Hello World";
	assert(s.length == 11);
	assert(s.empty == false);
	assert(s == s);
	assert(s == "Hello World");

	assert(s[0] == 'H');

	string dStr = s.toString();
	assert(dStr == "Hello World");

	String s2 = s[6 .. 11];
	assert(s2 == "World");

	String s3;
	s3 ~= "Hello";
	s3 ~= " ";
	s3 ~= "World";
	assert(s3 == s);

	String s4 = s ~ " " ~ s3;
	assert(s4 == "Hello World Hello World");

	//
	// getWriter returns a voldemort type that works with
	// std.format.formattedWrite
	//
	String buffer;
	auto writer = buffer.getWriter();
	std.format.formattedWrite(writer, "%s %s", "Hello", "World");
	assert(buffer == "Hello World");
}

public struct String {
@safe:
	Payload impl;
	private uint theLength;

	this(string input) @trusted {
		if(input.length > SmallStringMaxSize) {
			this.allocate(input.length);
			this.impl.ptr.ptr[0 .. input.length] = cast(char[])input[];
		} else {
			this.impl.small[0 .. input.length] = input;
		}
		this.theLength = cast(uint)input.length;
	}

	this(ref return scope String n) @trusted {
		if(n.length > SmallStringMaxSize) {
			this.impl.ptr = n.impl.ptr;
			this.impl.ptr.refCnt++;
		} else {
			this.impl.small = n.impl.small;
		}

		this.theLength = n.length;
	}

	~this() @trusted {
		if(this.theLength > SmallStringMaxSize) {
			this.impl.ptr.refCnt--;
			if(this.impl.ptr.refCnt <= 0) {
				GC.free(this.impl.ptr.ptr);
				GC.free(this.impl.ptr);
			}
		}
	}

	@property uint length() const @safe {
		return this.theLength;
	}

	@property bool empty() const nothrow {
		return this.theLength == 0;
	}

	version(unittest) {
		PayloadHeap* getPayload() @trusted {
			return this.theLength < SmallStringMaxSize
				? null
				: this.impl.ptr;
		}
	}

	char opIndex(size_t idx) const {
		if(idx > this.length) {
			throw new Exception("The index must not be greater than "
					~ "the length of the String to slice");
		}
		return this.getData()[idx];
	}

	String opSlice(size_t low, size_t high) {
		if(low > high) {
			throw new Exception("The low slice index must not be greater than "
					~ "the high slice index");
		}
		if(high > this.length) {
			throw new Exception("The high slice index must not be greater than "
					~ "the length of the String to slice");
		}
		return String(this.getData()[low .. high]);
	}

	String opBinary(string op,S)(S other) @trusted
			if(op == "~")
	{
		String ret;

		const newLen = this.theLength + other.length;
		ret.theLength = cast(uint)newLen;

		static if(is(S == string)) {
			if(newLen < SmallStringMaxSize) {
				ret.impl.small[0 .. this.theLength] = cast(char[])this.getData();
				ret.impl.small[this.theLength .. newLen] = other;
			} else {
				ret.allocate(newLen);	
				ret.impl.ptr.ptr[0 .. this.theLength] = cast(char[])this.getData();
				ret.impl.ptr.ptr[this.theLength .. newLen] = cast(char[])other;
			}
		} else static if(is(S == String)) {
			if(newLen < SmallStringMaxSize) {
				ret.impl.small[0 .. this.theLength] = cast(char[])this.getData();
				ret.impl.small[this.theLength .. newLen] = cast(char[])other.getData();
			} else {
				ret.allocate(newLen);	
				ret.impl.ptr.ptr[0 .. this.theLength] = cast(char[])this.getData();
				ret.impl.ptr.ptr[this.theLength .. newLen] = cast(char[])other.getData();
			}
		}

		return ret;
	}

	void opOpAssign(string op,S)(S other) @trusted
			if(op == "~")
	{
		const newLen = this.theLength + other.length;

		if(newLen >= SmallStringMaxSize && this.theLength < SmallStringMaxSize) {
			char[SmallStringMaxSize] copy = this.impl.small[];
			this.allocate(newLen);
			this.impl.ptr.ptr[0 .. this.theLength] = copy[0 .. this.theLength];
		} else if(newLen >= SmallStringMaxSize && this.theLength > SmallStringMaxSize) {
			this.realloc(newLen);
		}

		static if(is(S == string)) {
			if(newLen < SmallStringMaxSize) {
				this.impl.small[this.theLength .. newLen] = other;
			} else {
				this.impl.ptr.ptr[this.theLength .. newLen] = cast(char[])other;
			}
		} else static if(is(S == String)) {
			if(newLen < SmallStringMaxSize) {
				this.impl.small[this.theLength .. newLen] = cast(char[])other.getData();
			} else {
				this.impl.ptr.ptr[this.theLength .. newLen] = cast(char[])other.getData();
			}
		}

		this.theLength = cast(uint)newLen;
	}

	bool opEquals(string s) const {
		return this.getData() == s;
	}

	bool opEquals(const ref String s) const {
		return this.getData() == s;
	}

	auto getWriter() {
		struct StringWriter {
			String* buf;
		
			void put(const(char)[] data) @system {
				(*buf) ~= cast(string)data;
			}
		}

		return StringWriter(&this);
	}

	string toString() const {
		return this.getData().idup();
	}

	private void realloc(const size_t newLen) @trusted {
		if(this.theLength < SmallStringMaxSize) {
			this.allocate(newLen);
		} else {
			this.impl.ptr.ptr = cast(char*)GC.realloc(this.impl.ptr.ptr, newLen);
		}
	}

	private void allocate(const size_t newLen) @trusted {
		this.impl.ptr = cast(PayloadHeap*)GC.malloc(PayloadHeap.sizeof);
		this.impl.ptr.ptr = cast(char*)GC.malloc(newLen);
		this.impl.ptr.refCnt = 1;
	}

	private string getData() const @trusted {
		return cast(string)(this.theLength < SmallStringMaxSize
			? this.impl.small[0 .. this.theLength]
			: this.impl.ptr.ptr[0 .. this.theLength]
		);
	}
}

private struct PayloadHeap {
	long refCnt;
	char* ptr;
}

enum SmallStringMaxSize = 56;

private union Payload {
	char[SmallStringMaxSize] small;
	PayloadHeap* ptr;
}

unittest {
	static assert(String.sizeof == 64);
}

unittest {
	auto s = String("Hello World");
}

unittest {
	auto t = String("Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World");
}

unittest {
	auto r = String("Hello") ~ " World";
	assert(r.getData() == "Hello World", r.getData());

	String g;
	g ~= "Hello World Hello World Hello World Hello World";
	g ~= "Hello World Hello World Hello World Hello World";
	g ~= "Hello World Hello World Hello World Hello World";
}

unittest {
	String g;
	g ~= "Hello World Hello World Hello World Hello World";
	String l = g;

	g ~= "Hello World Hello World Hello World Hello World";
	g ~= "Hello World Hello World Hello World Hello World";

	String h = g;
	String j = h;
}

unittest {
	String a;
	a = a;
	a = String("Hello World");
}

unittest {
	string s = "Hello World";
	String a = String(s);
	foreach(idx, char c; s) {
		assert(a[idx] == c);
	}
}

unittest {
	String fun() {
		auto t = String("Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World");
		assert(t.getPayload.refCnt == 1);
		return t;
	}

	String s;
	assert(s.getPayload is null);
	s = fun();
	assert(s.getPayload.refCnt == 1);
}

unittest {
	void bar(String s) {
		assert(s.getPayload.refCnt == 3);
	}

	void fun(String s) {
		assert(s.getPayload !is null);
		assert(s.getPayload.refCnt == 2);
		bar(s);
	}

	auto t = String("Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World");

	fun(t);
}

unittest {
	auto t = String("Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World");

	String s1 = t[12 .. 17];
	assert(s1 == "Hello");

	auto s = String("Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World");
	assert(s == t);
	assert(t == s);

	assert(s1 != t);
	assert(t != s1);
}

unittest {
	auto s = String("Hello World");
	auto t = String("Hello World");
	assert(s == t);
	assert(t == s);
}

unittest {
	String buf;
	auto writer = buf.getWriter();
	formattedWrite(writer, "%s", "Hello");
	assert(buf == "Hello", buf.getData());
}

unittest {
	String buf;
	auto writer = buf.getWriter();
	foreach(_; 0 .. 100) {
		formattedWrite(writer, "%s", "Hello");
	}
	assert(buf.length == 500);
}

unittest {
	auto s = String("Hello World");
	string ss = s.toString();
	assert(ss == "Hello World");
}

unittest {
	String buf;
	auto writer = buf.getWriter();
	formattedWrite(writer, "%128s", "Hello");
	String len;
	auto w2 = len.getWriter();
	formattedWrite(w2, "%s", buf.length);
	assert(buf.length == 128, len.getData());
}
