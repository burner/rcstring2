module rcstring2;

import std.stdio;

import core.memory : GC;

private struct PayloadHeap {
	long refCnt;
	char* ptr;
}

enum SmallStringMaxSize = 56;

private union Payload {
	char[SmallStringMaxSize] small;
	PayloadHeap* ptr;
}

public struct String {
	Payload impl;
	private uint theLength;

	@property uint length() const @safe {
		return this.theLength;
	}

	this(string input) {
		if(input.length > SmallStringMaxSize) {
			this.allocate(input.length);
			this.impl.ptr.ptr[0 .. input.length] = cast(char[])input[];
		} else {
			this.impl.small[0 .. input.length] = input;
		}
		this.theLength = cast(uint)input.length;
	}

	this(ref return scope String n) {
		if(n.length > SmallStringMaxSize) {
			this.impl.ptr = n.impl.ptr;
			this.impl.ptr.refCnt++;
			writeln(__LINE__);
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

	@property bool empty() const nothrow {
		return this.theLength == 0;
	}

	version(unittest) {
		PayloadHeap* getPayload() {
			return this.theLength < SmallStringMaxSize
				? null
				: this.impl.ptr;
		}
	}

	string getData() const @system {
		return cast(string)(this.theLength < SmallStringMaxSize
			? this.impl.small[0 .. this.theLength]
			: this.impl.ptr.ptr[0 .. this.theLength]
		);
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
				ret.impl.ptr.ptr[0 .. this.theLength] = cast(char[])this.impl.getData();
				ret.impl.ptr.ptr[this.theLength .. newLen] = cast(char[])other.getData();
			}
		}

		return ret;
	}

	void opOpAssign(string op,S)(S other) @trusted
			if(op == "~")
	{
		const newLen = this.theLength + other.length;

		if(newLen > SmallStringMaxSize && this.theLength < SmallStringMaxSize) {
			char[SmallStringMaxSize] copy = this.impl.small[];
			this.allocate(newLen);
			this.impl.ptr.ptr[0 .. this.theLength] = copy[0 .. this.theLength];
		} else if(newLen > SmallStringMaxSize && this.theLength > SmallStringMaxSize) {
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
