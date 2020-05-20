/// Implements a C#-style multicast delegate which is simply a collection of
/// delegates acting like one single delegate.
///
/// All functionality is in the type $(LREF MulticastImpl) with a helper
/// construction function called $(LREF multicast).
///
/// Use $(LREF Multicast) for an API which asserts out if you attempt to call
/// uninitialized Multicast values or $(LREF MulticastOpt) for an API which
/// simply does nothing when called with uninitialized values.
///
/// Authors: webfreak
/// License: released in the public domain under the unlicense, see LICENSE
module multicast_delegate;

// version = CSharpCompat;

import std.algorithm : remove;
import std.functional : forward;
import std.traits : FunctionAttribute, functionAttributes,
	functionLinkage, isDelegate, isFunctionPointer,
	Parameters, ReturnType, SetFunctionAttributes, Unqual;

@safe:

static if (is(size_t == ulong))
	private enum needsCopyBit = 1UL << 63UL;
else
	private enum needsCopyBit = cast(size_t)(
				1 << (8 * size_t.sizeof - 1));

version (unittest)
{
	private int dupCount;
}

/// Constructs a multicast delegate from a variadic list of delegates.
Multicast!Del multicast(Del)(Del[] delegates...)
		if (isDelegate!Del || isFunctionPointer!Del)
{
	return Multicast!Del(delegates);
}

/// MulticastDelegate API which asserts out if you attempt to call it with an
/// empty list.
alias Multicast(Del) = MulticastImpl!(Del, true);

/// MulticastDelegate API which simply does nothing if you attempt to call it
/// with an empty list. Returns the init value and performs no out/ref
/// modifications.
alias MulticastOpt(Del) = MulticastImpl!(Del, false);

/// Full multicast delegate implementation of this package. Modification
/// operations are nothrow, pure, @safe and if possible @nogc. Using the `@nogc`
/// overloads it's possible to use all functionality. Invocation inherits the
/// attributes of the delegate or function pointer.
///
/// Even though the multicast implementation acts like a reference type, it is
/// actually a value type and not a reference type, so modifications of copies
/// will not be reflected in the source object. While normal copying by passing
/// around the multicast delegate by value doesn't copy the underlying array
/// data, this data structure will track copies and perform a copy on write
/// whenever state is changed in a way that would affect other instances. Relies
/// on GC to cleanup duplicated arrays.
///
/// When a multicast delegate is invoked (converted to a normal delegate and
/// invoked), all methods are called in order. Reference parameters will be
/// forwarded and passed sequentially to each method. Any changes in reference
/// parameters are visible to the next method. When any of the methods throws an
/// exception that is not caught within the method, that exception is passed to
/// the caller of the delegate and no subsequent methods in the invocation list
/// are called. If the delegate has a return value and/or out parameters, it
/// returns the return value and parameters of the last method invoked.
///
/// Function attributes for delegates and function pointers are inherited to the
/// simulated delegate. Function pointers are changed to being delegates however
/// and the linkage of the delegate will be `extern(D)` as other linkage doesn't
/// make sense for D delegates.
///
/// This is a lot like the MulticastDelegate type in C#, which performs the same
/// operations. See$(BR)
/// $(LINK https://docs.microsoft.com/en-us/dotnet/csharp/programming-guide/delegates/using-delegates)$(BR)
/// $(LINK https://docs.microsoft.com/en-us/dotnet/csharp/programming-guide/delegates/how-to-combine-delegates-multicast-delegates)$(BR)
/// $(LINK https://docs.microsoft.com/en-us/dotnet/api/system.multicastdelegate?view=netcore-3.1)$(BR)
///
/// There are optional C#-style method overloads for + and - as well as an added
/// GetInvocationList method which simply returns the delegates. To use these,
/// compile the library with `version = CSharpCompat;`.
///
/// Params:
///    Del = the delegate or function pointer type which this MulticastImpl
///          simulates. In case of function pointers this will be a delegate of
///          the same return value, parameters and attributes.
///
///    assertIfNull = if true, crash with assert(false) in case you try to call
///          an instance with no delegates set.
struct MulticastImpl(Del, bool assertIfNull)
		if (isDelegate!Del || isFunctionPointer!Del)
{
	union
	{
		/// The list of delegates or function pointers. This is an internal
		/// field to the struct which may be tainted with an extra bit,
		/// corrupting any attempted use or modification. Use the
		/// $(LREF delegates) property to get or set the list of delegates
		/// instead. Use `add` and `remove` to perform efficient adding and
		/// removing which takes care of memory ownership.
		Del[] _delegates;

		/// Magic storage of a copy bit which is set when a postblit occurs to
		/// signal that mutating functions (except add) must copy the delegates
		/// array before modification.
		size_t _accessMask;
	}

	/// Constructs this multicast delegate without any value, same as init.
	this(typeof(null)) nothrow pure @nogc immutable
	{
	}

	/// Constructs this multicast delegate with a singular delegate to call.
	this(Del one) nothrow pure immutable @trusted
	{
		_delegates = [one];
	}

	/// Constructs this multicast delegate with a given array of delegates. Does
	/// not duplicate the array, so future modifications might change the
	/// behavior of this delegate. It is recommended only to use this for @nogc
	/// compatibility.
	this(immutable(Del)[] all) nothrow pure @nogc immutable @trusted
	{
		_delegates = all;
		(cast() this)._accessMask |= needsCopyBit;
	}

	/// ditto
	this(Del[] all) nothrow pure @nogc @trusted
	{
		_delegates = all;
	}

	this(this)
	{
		_accessMask |= needsCopyBit;
	}

	/// Returns the _delegates member with the magic access mask storage
	/// stripped away for normal usage.
	inout(Del[]) delegates() inout nothrow pure @nogc @trusted
	{
		const mask = _accessMask;
		cast() _accessMask &= ~needsCopyBit;
		inout(Del[]) ret = _delegates;
		cast() _accessMask = mask;
		return ret;
	}

	/// Sets the _delegates member and resets the magic copy bit.
	ref auto delegates(Del[] all) nothrow pure @nogc @trusted
	{
		_accessMask &= ~needsCopyBit;
		_delegates = all;
		return this;
	}

	/// Adds one or more delegates to this multicast delegate in order. Returns
	/// a reference to this instance.
	ref auto add(const Del[] dels) nothrow pure @trusted
	{
		const copyBit = (_accessMask & needsCopyBit) != 0;
		_accessMask &= ~needsCopyBit;
		const ptr = _delegates.ptr;
		scope (exit)
			if (copyBit && _delegates.ptr == ptr)
				_accessMask |= needsCopyBit;
		_delegates ~= dels;
		return this;
	}

	/// ditto
	ref auto add(bool v)(const MulticastImpl!(Del, v) del) nothrow pure @trusted
	{
		const copyBit = (_accessMask & needsCopyBit) != 0;
		_accessMask &= ~needsCopyBit;
		const ptr = _delegates.ptr;
		scope (exit)
			if (copyBit && _delegates.ptr == ptr)
				_accessMask |= needsCopyBit;
		_delegates ~= del.delegates;
		return this;
	}

	/// ditto
	ref auto add(const Del del) nothrow pure @trusted
	{
		const copyBit = (_accessMask & needsCopyBit) != 0;
		_accessMask &= ~needsCopyBit;
		const ptr = _delegates.ptr;
		scope (exit)
			if (copyBit && _delegates.ptr == ptr)
				_accessMask |= needsCopyBit;
		_delegates ~= del;
		return this;
	}

	/// Removes a delegate from this multicast delegate. Returns a reference to
	/// this instance. Note that this will duplicate the array in case this
	/// delegate did not create it.
	ref auto remove(const Del del) nothrow pure @trusted
	{
		if ((_accessMask & needsCopyBit) != 0)
		{
			_accessMask &= ~needsCopyBit;
			_delegates = _delegates.dup.remove!(
					a => a == del);

			version (unittest)
				debug dupCount++;
		}
		else
		{
			_delegates = _delegates.remove!(a => a == del);
		}

		return this;
	}

	/// Removes a delegate from this multicast delegate, assumes this instance
	/// holds a unique reference to the delegates array. If this is called on
	/// copies of this multicast instance, change in behavior may occur.
	ref auto removeAssumeUnique(const Del del) nothrow pure @nogc @trusted
	{
		_delegates = _delegates.remove!(a => a == del);
		return this;
	}

	/// Reassigns this multicast delegate to a single delegate. Returns a
	/// reference to this instance.
	ref auto opAssign(const Del one) nothrow pure
	{
		delegates = [one];
		return this;
	}

	/// Reassigns this multicast delegate with a given array of delegates. Does
	/// not duplicate the array, so future modifications might change the
	/// behavior of this delegate. It is recommended only to use this for @nogc
	/// compatibility. Returns a reference to this instance.
	ref auto opAssign(Del[] all) nothrow pure @nogc
	{
		delegates = all;
		return this;
	}

	/// Unsets this multicast delegate to the init state.
	ref auto opAssign(typeof(null)) nothrow pure @nogc @trusted
	{
		_accessMask &= ~needsCopyBit;
		_delegates = null;
		_accessMask = 0;
		return this;
	}

	/// Overloads `~=` operator to call add.
	alias opOpAssign(string op : "~") = add;

	/// Overloads any binary operator (+, -, ~) to operate on a copy of this
	/// multicast delegate. Performs a duplication of the delegates array using
	/// the GC.
	auto opBinary(string op, T)(const T rhs) const
	{
		Unqual!(typeof(this)) copy;
		copy.delegates = delegates.dup;
		version (unittest)
			debug dupCount++;
		copy.opOpAssign!op(rhs);
		return copy;
	}

	/// Checks if there are any delegates and if this can be called.
	bool opCast(T : bool)() const nothrow pure @nogc @trusted
	{
		return _delegates.length > 0;
	}

	/// Implementation: actually calls the delegates for this multicast delegate.
	/// This has no function attributes set on it, so it's not recommended to be
	/// called manually.
	ReturnType!Del _invokeImpl(Parameters!Del params) const @trusted
	{
		const copyBit = (_accessMask & needsCopyBit) != 0;
		cast() _accessMask &= ~needsCopyBit;
		scope (exit)
			if (copyBit)
				cast() _accessMask |= needsCopyBit;

		if (!delegates.length)
		{
			static if (assertIfNull)
				assert(false, "Tried to call unassigned multicast delegate");
			else static if (is(typeof(return) == void))
				return;
			else
				return typeof(return).init;
		}

		foreach (Del del; _delegates[0 .. $ - 1])
			del(forward!params);
		return _delegates[$ - 1](forward!params);
	}

	/// Implementation: takes $(LREF _invokeImpl) as a delegate and adds the
	/// function attributes of the wrapping delegate. This may be considered an
	/// unsafe operation, especially with future added attributes which could
	/// change the behavior of a function call. The ABI is that of a normal
	/// `extern(D) T delegate(Args...) const @trusted` which gets changed to all
	/// the attributes of the wrapping delegate.
	auto _invokePtr() const nothrow pure @nogc @trusted
	{
		return cast(SetFunctionAttributes!(typeof(&_invokeImpl),
				"D", functionAttributes!Del))&_invokeImpl;
	}

	/// Converts this multicast delegate to a normal delegate. This is also used
	/// as `alias this`, so this multicast delegate can be passed as delegate
	/// argument to functions or be called directly.
	alias toDelegate = _invokePtr;

	/// ditto
	alias toDelegate this;

	version (CSharpCompat)
	{
		/// Adds `+=` operator support for C# code compatibility
		alias opOpAssign(string op : "+") = add;

		/// Adds `-=` operator support for C# code compatibility
		alias opOpAssign(string op : "-") = remove;

		/// Returns the delegates of this multicast.
		auto GetInvocationList() const nothrow pure @nogc
		{
			return delegates;
		}
	}
}

///
@system unittest
{
	int modify1(ref string[] stack)
	{
		stack ~= "1";
		return cast(int) stack.length;
	}

	int modify2(ref string[] stack)
	{
		stack ~= "2";
		return 9001;
	}

	string[] stack;

	// del is like a delegate now
	Multicast!(int delegate(ref string[])) del = &modify1;
	assert(del(stack) == 1);
	assert(stack == ["1"]);

	stack = null;
	del ~= &modify2;
	assert(del(stack) == 9001);
	assert(stack == ["1", "2"]);

	void someMethod(int delegate(ref string[]) fn)
	{
	}

	someMethod(del);
	someMethod(del);
}

@safe unittest
{
	import std.exception;
	import core.exception;

	string[] calls;

	void call1()
	{
		calls ~= "1";
	}

	void call2()
	{
		calls ~= "2";
	}

	Multicast!(void delegate() @safe) del;
	MulticastOpt!(void delegate() @safe) delOpt;

	(() @trusted => assertThrown!AssertError(del()))();
	delOpt();

	del = &call1;
	del();
	assert(calls == ["1"]);

	calls = null;
	delOpt = &call1;
	delOpt();
	assert(calls == ["1"]);

	calls = null;
	del();
	assert(calls == ["1"]);

	calls = null;
	del();
	del();
	assert(calls == ["1", "1"]);

	calls = null;
	del ~= &call1;
	del();
	assert(calls == ["1", "1"]);

	calls = null;
	del ~= &call2;
	del();
	assert(calls == ["1", "1", "2"]);
}

@safe unittest
{
	alias Del = int delegate(long) @safe nothrow @nogc pure;

	int fun1(long n) @safe nothrow @nogc pure
	{
		return cast(int)(n - 1);
	}

	int fun2(long n) @safe nothrow @nogc pure
	{
		return cast(int)(n - 2);
	}

	Multicast!Del foo = [&fun1, &fun2];

	assert((() nothrow @nogc pure => foo(8))() == 6);

	void someMethod(Del fn)
	{
		fn(4);
	}

	someMethod(foo);
}

@safe unittest
{
	import std.exception;

	alias Del = void delegate() @safe;

	int[] stack;

	void f1()
	{
		stack ~= 1;
	}

	void f2()
	{
		stack ~= 2;
		throw new Exception("something occurred");
	}

	void f3()
	{
		stack ~= 3;
	}

	Multicast!Del something;
	something ~= &f1;
	something ~= &f2;
	something ~= &f3;

	assertThrown(something());
	assert(stack == [1, 2]);
}

@safe unittest
{
	alias Del = void function(ref int[]) @safe;

	int[] stack;

	static void f1(ref int[] stack) @safe
	{
		stack ~= 1;
	}

	static void f2(ref int[] stack) @safe
	{
		stack ~= 2;
	}

	Multicast!Del something;
	something ~= &f1;
	something ~= &f2;

	something(stack);
	assert(stack == [1, 2]);

	stack = null;
	(something ~ &f2)(stack);
	assert(stack == [1, 2, 2]);

	stack = null;
	const Multicast!Del constSomething = &f1;

	constSomething(stack);
	assert(stack == [1]);

	stack = null;
	(constSomething ~ &f2)(stack);
	assert(stack == [1, 2]);

	stack = null;
	immutable Multicast!Del immutableSomething = &f1;
	immutable Multicast!Del immutableSomething2 = [
		&f1, &f2
	];

	immutableSomething(stack);
	assert(stack == [1]);

	stack = null;
	(immutableSomething ~ &f2)(stack);
	assert(stack == [1, 2]);
}

@safe unittest
{
	alias Del = void function(ref int[]) @safe;

	int[] stack;

	static void f1(ref int[] stack) @safe
	{
		stack ~= 1;
	}

	static void f2(ref int[] stack) @safe
	{
		stack ~= 2;
	}

	Multicast!Del something;
	something ~= &f1;
	something ~= &f2;

	Multicast!Del copy = something;
	copy.remove(&f1);

	something(stack);
	assert(stack == [1, 2]);

	stack = null;
	copy(stack);
	assert(stack == [2]);
}

@system debug unittest
{
	dupCount = 0;

	alias Del = void function(ref int[]) @safe;

	int[] stack;

	static void f1(ref int[] stack) @safe
	{
		stack ~= 1;
	}

	static void f2(ref int[] stack) @safe
	{
		stack ~= 2;
	}

	Multicast!Del something;
	something ~= &f1;
	something ~= &f2;
	assert(dupCount == 0);

	Multicast!Del copy = something;
	assert(dupCount == 0);
	something(stack);
	copy(stack);
	assert(dupCount == 0);

	copy.remove(&f1);
	assert(dupCount == 1);
}

@safe unittest
{
	alias Del = void function();
	Multicast!Del something;
	Multicast!Del somethingNull = null;
	something = null;

	MulticastOpt!Del somethingOpt;
	MulticastOpt!Del somethingOptNull = null;
	somethingOpt = null;

	const MulticastOpt!Del somethingConstNull = null;
	immutable MulticastOpt!Del somethingImmutableNull = null;
}
