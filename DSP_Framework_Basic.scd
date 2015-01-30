(
//Use a dictionary to organize your code
q = ();
q[\synths] = ();
//Set up Groups for stability and to assure an order of operations chain on the computing side
q[\g0] = Group.new(s);
q[\g1] = Group.after(q[\g0]);
q[\g2] = Group.after(q[\g1]);
q[\g3] = Group.after(q[\g2]);
q[\g99] = Group.after(q[\g3]);

//Make the synth def
//sending the audio to a private bus
SynthDef(\soundin_mono,{
	arg inbus, outbus, amp=1.0, atk=0.06, decay=0, sus=1.0, rel=0.1, crv= -2, gate=1;
	var in, env;
	env = EnvGen.ar( Env.adsr(atk, decay, sus, rel, curve:crv), gate );
	in = SoundIn.ar(inbus);
	Out.ar(outbus, in*amp*env);
}).add;

SynthDef(\soundout_mono,{
	arg inbus, outbus, amp=1.0, atk=0.06, decay=0, sus=1.0, rel=0.1, crv= -2, gate=1;
	var in, env;
	env = EnvGen.ar( Env.adsr(atk, decay, sus, rel, curve:crv), gate );
	in = In.ar(inbus);
	Out.ar(outbus, in*amp*env);
}).add;

SynthDef(\dringmod,{
	arg inbus, outbus, atk=0.1, decay=0, sus=1.0, rel=0.1, crv= -2, gate=1, rate=0.2, range=0.5;
	var car, dsp, mod, freq, env, lfopitch, basepitch;
	env = EnvGen.ar( Env.adsr(atk, decay, sus, rel, curve:crv), gate );
	basepitch = \pitch.kr(60, 0.01);
	lfopitch = SinOsc.kr(rate).range(basepitch-range, basepitch+range);
	freq = lfopitch.midicps;
	car = In.ar(inbus);
	mod = SinOsc.ar( freq, mul: \modamp.kr(1, 0.01) );
	dsp = DiodeRingMod.ar(car, mod);
	Out.ar( outbus, dsp * \amp.kr(1.0, 0.01) * env);
}).add;

SynthDef(\guitaramp,{
	arg inbus, outbus, amp=1.0, atk=0.06, decay=0, sus=1.0, rel=0.1, crv= -2, gate=1;
	var in, env, amount, amCoef, sig;
	env = EnvGen.ar( Env.adsr(atk, decay, sus, rel, curve:crv), gate );
	in = HPF.ar(In.ar(inbus), 400)*5;
	amount = 0.99;
	amCoef= 2*amount/(1-amount);
	sig = MidEQ.ar(LPF.ar((1+amCoef)*in/(1+(amCoef*in.abs)), [3800, 3900])*0.5, 120, 0.7, 8);
	Out.ar(outbus, sig*amp*env);
}).add;


//Make an oscdef to create a sound in on the fly
OSCdef(\mksoundin, {
	arg msg;
	var name, outbus, inbus;
	//give it a name from msg[1] and store it
	//in our dictionary under that name
	//this allows us to do this on the fly
	name = msg[1].asSymbol;
	//check if this name already exists
	//only add if does not exist
	if(q[\synths].includesKey(name) == false,{
		//create a private audio bus for the
		//source to go to
		//this allows for dynamic repatching later
		outbus = Bus.audio(s);
		//get inbus from second msg argument - msg[2]
		inbus = msg[2].asInteger;
		//create an array under dictionary name
		//with a standard template - inbus, outbus, synth
		//this allows us to access all of these on the fly and at a later date
		q[\synths][name] = [
			// 0 - inbus (in this case nil as this is a source and there is no inbus)
			inbus,
			// 1 - outbus, the audio bus we created earlier
			outbus,
			// 2 - synth
			Synth( \soundin_mono, [\inbus, inbus, \outbus, outbus], q[\g0] )
		]
	})
}, "/mksoundin");

//Make an oscdef to create a sound in on the fly
OSCdef(\mksoundout, {
	arg msg;
	var name, outbus, inbus;
	name = msg[1].asSymbol;
	if(q[\synths].includesKey(name) == false,{
		inbus = Bus.audio(s);
		outbus = msg[2].asInteger;
		q[\synths][name] = [
			inbus,
			outbus,
			Synth( \soundout_mono, [\inbus, inbus, \outbus, outbus], q[\g99] )
		]
	})
}, "/mksoundout");

//Make an oscdef to create a sound in on the fly
OSCdef(\mkdsp, {
	arg msg;
	var name, sdname, outbus, inbus, group;
	name = msg[1].asSymbol;
	sdname = msg[2].asSymbol;
	group = q[ ("g"++msg[3]).asSymbol ];
	group.postln;
	if(q[\synths].includesKey(name) == false,{
		inbus = Bus.audio(s);
		outbus = Bus.audio(s);
		q[\synths][name] = [
			inbus,
			outbus,
			Synth( sdname, [\inbus, inbus, \outbus, outbus], group )
		]

	})
}, "/mkdsp");

OSCdef(\kill, {
	arg msg;
	var name;
	//msg[1] is key name in dictionary
	name = msg[1].asSymbol;
	//check if ksy is there
	if( q[\synths].includesKey(name), {
		q[\synths][name][0].free; // free inbus
		q[\synths][name][1].free; // free outbus
		q[\synths][name][2].free; //free synth
		q[\synths].removeAt(name) //eliminate dictionary entry
	})
}, "/kill");

OSCdef(\chgargs, {
	arg msg;
	var name, args_vals;
	name = msg[1].asSymbol;
	// Copies incomming args from msg from msg[2] on
	args_vals = msg.copyRange(2, msg.size);
	//Keeps data types right - symbol/float pairs (prusuming all argument values are floats)
	args_vals.do{ |it, ix| if(ix.even, {args_vals[ix]=it.asSymbol}, {args_vals[ix]=it.asFloat}) };
	if( q[\synths].includesKey(name), {
		args_vals.do{ |it ix|
		//3rd member of the synth array is always the synth
			if( ix.odd, { q[\synths][name][2].set( args_vals[ix-1], it ) } ); //args_vals is already and array
		}
	})
}, "/chgargs");

OSCdef(\route, {
	arg msg;
	var fromname, toname;
	fromname = msg[1].asSymbol;
	toname = msg[2].asSymbol;
	if( q[\synths].includesKey(fromname) && q[\synths].includesKey(toname), {
		q[\synths][toname][2].set(\inbus, q[\synths][fromname][1]);
	})
}, "/route");

OSCdef(\unroute, {
	arg msg;
	var name;
	name = msg[1].asSymbol;
	if( q[\synths].includesKey(name), {
		q[\synths][name][2].set(\inbus, q[\synths][name][0]);
	})
}, "/unroute");

)
//LIST OF OSC COMMANDS
/*
/mksoundin(name, in channel number)
/mksoundout(name, out channel number)
/mkdsp(name, synthdef name, group number)
/kill(name)
/chgargs(name, argname/val pairs...)
/route(from name, to name)
*/

//SC Test Code
s.meter;
s.queryAllNodes;
n = NetAddr.localAddr;

n.sendMsg("/mksoundin", "mic1", 0);
n.sendMsg("/mksoundout", "out1", 0);
n.sendMsg("/route", "mic1", "out1");
n.sendMsg("/unroute","out1");

n.sendMsg("/mkdsp", "rm", "dringmod", 1);
n.sendMsg("/route", "mic1", "rm");
n.sendMsg("/route", "rm", "out1");
n.sendMsg("/unroute","out1");

n.sendMsg("/mkdsp", "ga", "guitaramp", 1);
n.sendMsg("/route", "mic1", "ga");
n.sendMsg("/route", "ga", "out1");
n.sendMsg("/unroute","out1");

n.sendMsg("/mkdsp", "rm", "dringmod", 1);
n.sendMsg("/route", "mic1", "rm");
n.sendMsg("/route", "rm", "ga");
n.sendMsg("/route", "ga", "out1");
n.sendMsg("/unroute","out1");

n.sendMsg("/chgargs", "rm", "pitch", 70, "modamp", 0.7, "range", 2, "rate", 0.3);
g = EZSlider(controlSpec:ControlSpec(50.0, 80.0), action:{|ez| n.sendMsg("/chgargs", "rm", "pitch", ez.value)});
n.sendMsg("/chgargs", "mic1", "gate", 0);
n.sendMsg("/chgargs", "mic1", "gate", 1);
n.sendMsg("/chgargs", "rm", "gate", 0);
n.sendMsg("/chgargs", "rm", "gate", 1);
n.sendMsg("/chgargs", "out1", "gate", 0);
n.sendMsg("/chgargs", "out1", "gate", 1);
n.sendMsg("/kill", "ga");
n.sendMsg("/kill", "rm");
n.sendMsg("/kill", "out1");
n.sendMsg("/kill", "mic1");


//make simple gui in processing
//killall
//put in initialization sequence
//develop a few dsp:
////granulation
////impulse verb
////amplitude tracking synthesis
////phasor etc.
////amplitude tracking sample trigger






	(

		//Initialization Sequence
		~init = {
			s.waitForBoot{
				fork{
					1.postln;
					//Add SynthDefs
					//Make Busses
					//Load Buffers
					//Make Groups
					0.1.wait;

					2.postln;
					//Functions
					//OSC Defs
					0.1.wait;

					3.postln;
					//Routines
					0.1.wait;

					4.postln;
					//GUI
					{

					}.defer
				}
		}};

		//Exit Sequence
		~exit = {
			fork{
				1.postln;

				0.1.wait;

				2.postln;

				0.1.wait;

				3.postln;

				0.1.wait;
		}};

		//Initialization OSCified
		//// Using this, you can initialize remotely
		OSCdef( \init, {~init.value}, "/init" );
		//Exit OSCified
		//// Using this, you can exit remotely
		OSCdef( \exit, {~exit.value}, "/exit" );
	)

	a = NetAddr("localhost", 57120);
	a.sendMsg("/init");
	a.sendMsg("/exit");
	