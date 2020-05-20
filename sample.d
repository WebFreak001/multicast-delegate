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

		// or construct it immutable
		immutable Multicast!SomeDelegate fixed = multicast(&func2, &func2);

		// concat multiple and call a normal delegate method
		runCallback(multi ~ fixed); // implicitly using Multicast!T as delegate
}