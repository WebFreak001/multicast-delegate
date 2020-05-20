# multicast-delegate

C-Sharp style MulticastDelegate, allows combining and calling multiple delegates
into one. Transparently works with third party libraries, works with `@safe`,
`nothrow`, `pure` and has APIs to use with `@nogc`. The library works well with
`const` and `immutable` as well and the data structure is simply a safe and
efficient wrapper around delegate arrays. Offers consistent D-style operator
overloading using the `~` concatenation operator as well as C# compatible `+`
and `-` operators for calling the add and remove functions.

* Allows you to define APIs with more flexible callbacks
* Allows you to use this as C# style event system
* Allows you to write arbitrary depth callbacks with return values and out/ref
* Uses idiomatic features with full integration of language features

To use in your dub project simply run
```
dub add multicast-delegate
```

To use with additional C# compatibility types, add
```js
"subConfigurations": {
	"multicast-delegate": "cs-compat"
}
```
to your dub.json or add
```sdl
// dub.sdl
subConfiguration "multicast-delegate" "cs-compat"
```
to your dub.sdl.

To use elsewhere, just copy the
[source/multicast_delegate.d](source/multicast_delegate.d) file into your
project and import it using `import multicast_delegate`.

## Example

```d
import std.stdio;
import multicast_delegate; // I recommend using `public import` for all
                           // your common imports in some helper file

// have documented delegate types for your callbacks
alias SomeDelegate = void delegate();

// define your APIs as usual
void runCallback(SomeDelegate dg) { dg(); }

void main() {
	void func1() { writeln("1"); }
	void func2() { writeln("2"); }

	writeln("\ncalling normal delegate");
		// call like normal
		runCallback(&func1);

	writeln("\ncalling multicast delegates");
		// or call with multiple delegates in a row
		runCallback(multicast(&func1, &func2));

	writeln("\ncalling more delegates");
		// or store more complex delegate groups
		Multicast!SomeDelegate multi = &func1;
		// mutate it!
		multi ~= &func2;

		// or construct it immutable or const
		immutable Multicast!SomeDelegate fixed = multicast(&func2, &func2);

		// concat multiple and call a normal delegate method
		runCallback(multi ~ fixed); // implicitly using Multicast!T as delegate
}
```

outputs
```
calling normal delegate
1

calling multicast delegates
1
2

calling more delegates
1
2
2
2
```

## Documentation

http://multicast-delegate.dpldocs.info
