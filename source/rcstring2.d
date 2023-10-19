module rcstring2;

import core.memory : GC;

struct PayloadHeap {
	char* ptr;
	long refCnt;
	size_t capacity;
}

enum SmallStringMaxSize = 56;

union Payload {
	char[SmallStringMaxSize] small;
	PayloadHeap ptr;
}

public struct String {
	Payload impl;
	uint length;

	this(string input) {
		this.assign(input);
	}

	this(typeof(this) n) {
		this.assign(n);
	}

	this(this) {
		if(this.length > SmallStringMaxSize) {
			this.impl.ptr.refCnt++;
		}
	}

	~this() @trusted {
		if(this.length > SmallStringMaxSize) {
			this.impl.ptr.refCnt--;
			if(this.impl.ptr.refCnt <= 0) {
				GC.free(this.impl.ptr.ptr);
			}
		}
	}

	@property bool empty() const nothrow {
		return this.length == 0;
	}

	typeof(this) opBinary(string op,S)(S other) @trusted
			if(op == "~")
	{
		String ret;

		static if(is(S == string)) {
			const newLen = this.length + other.length;
			if(newLen < SmallStringMaxSize) {
				ret.impl.small[0 .. this.length] = this.impl.small;
				ret.impl.small[this.length .. newLen] = other;
			} else {
				ret.allocate(newLen);	
			}
		} else static if(is(S == String)) {
		}
	}

	private void assign(typeof(this) n) @trusted {
		if(this.length > SmallStringMaxSize) {
			this.impl.ptr.refCnt--;
			if(this.impl.ptr.refCnt <= 0) {
				GC.free(this.impl.ptr.ptr);
			}
		}

		if(n.length > SmallStringMaxSize) {
			this.impl.ptr = n.impl.ptr;
			this.impl.ptr.refCnt++;
		} else {
			this.impl.small = n.impl.small;
		}

		this.length = n.length;
	}

	private void assign(string input) @trusted {
		if(input.length > SmallStringMaxSize) {
			this.allocate(input.length);
			this.impl.ptr.ptr[0 .. input.length] = input;
		} else {
			this.impl.small[0 .. input.length] = input;
		}
		this.length = cast(uint)input.length;
	}

	private void allocate(const size_t newLen) @trusted {
		if(this.length <= SmallStringMaxSize) {
			this.impl.ptr = PayloadHeap.init;
		}
		if(newLen > SmallStringMaxSize) {
			this.impl.ptr.ptr = cast(char*)GC.realloc(this.impl.ptr.ptr, newLen);
			this.impl.ptr.refCnt = 1;
			this.impl.ptr.capacity = newLen;
		}
	}
}

unittest {
	static assert(String.sizeof == 64);

	auto s = String("Hello World");
	auto t = String("Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World Hello World");
}
