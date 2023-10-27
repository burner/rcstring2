# String is a reference counted, small string optimized string library.

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

```dlang
unittest {

	import rcstring2;

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
```

