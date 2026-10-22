/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef __DODGE_TRACE_H__
#define __DODGE_TRACE_H__
#include <linux/types.h>
void dodge_trace_map(void);
void dodge_trace(const char *tag, u32 arg);
void dodge_stop_splash(void);
#endif
