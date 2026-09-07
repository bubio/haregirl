// SPDX-License-Identifier: MPL-2.0
//
// NetBSD exposes siginfo_t with the same ABI on aarch64 and x86_64.  Hare
// currently supplies this definition only for NetBSD/x86_64; installing this
// file while bootstrapping Hare lets the NetBSD/aarch64 standard library build.
export type siginfo = struct {
	si_signo: int,
	si_errno: int,
	si_code: int,
	si_pid: pid_t,
	si_uid: uid_t,
	si_status: int,
	si_addr: *opaque,
	si_value: sigval,
	_reason: union {
		_fault: struct {
			_trapno: int,
		},
		_timer: struct {
			_timerid: int,
			_overrun: int,
		},
		_mesgq: struct {
			_mqd: int,
		},
		_poll: struct {
			_band: i64,
		},
		__spare__: struct {
			__spare1__: i64,
			__spare2__: [7]int,
		},
	},
};
