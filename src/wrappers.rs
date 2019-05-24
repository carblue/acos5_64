/*
 * wrapper.rs: Driver 'acos5_64' - Some wrapping functions
 *
 * Copyright (C) 2019  Carsten Blüggel <bluecars@posteo.eu>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, 51 Franklin Street, Fifth Floor  Boston, MA 02110-1335  USA
 */

/* naming: replace sc to wr, e.g. sc_do_log -> wr_do_log */

use std::os::raw::{c_uint, c_int, c_uchar};
use std::ffi::CStr;

use opensc_sys::opensc::{sc_context};
use opensc_sys::log::{sc_do_log, SC_LOG_DEBUG_NORMAL};


pub fn wr_do_log(ctx: *mut sc_context, file: &CStr, line: c_uint, fun: &CStr, fmt: &CStr)
{
    unsafe { sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, file.as_ptr(), line as c_int, fun.as_ptr(), fmt.as_ptr()) };
}

pub fn wr_do_log_t<T>(ctx: *mut sc_context, file: &CStr, line: c_uint, fun: &CStr, fmt: &CStr, arg: T)
{
    unsafe { sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, file.as_ptr(), line as c_int, fun.as_ptr(), fmt.as_ptr(), arg) };
}

pub fn wr_do_log_tu<T,U>(ctx: *mut sc_context, file: &CStr, line: c_uint, fun: &CStr, fmt: &CStr, arg1: T, arg2: U)
{
    unsafe { sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, file.as_ptr(), line as c_int, fun.as_ptr(), fmt.as_ptr(), arg1, arg2) };
}

pub fn wr_do_log_8u8_i32(ctx: *mut sc_context, file: &CStr, line: c_uint, fun: &CStr, fmt: &CStr, a: [c_uchar; 8], i:i32)
{
    unsafe { sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, file.as_ptr(), line as c_int, fun.as_ptr(), fmt.as_ptr(),
                       a[0] as u32, a[1] as u32, a[2] as u32, a[3] as u32, a[4] as u32, a[5] as u32, a[6] as u32, a[7] as u32, i) };
}

pub fn wr_do_log_zz(ctx: *mut sc_context, file: &CStr, line: c_uint, fun: &CStr, fmt: &CStr, arg1: usize, arg2: usize)
{
    unsafe { sc_do_log(ctx, SC_LOG_DEBUG_NORMAL, file.as_ptr(), line as c_int, fun.as_ptr(), fmt.as_ptr(), arg1, arg2) };
}