; -----------------------------------------------------------------------------
;
; TNKernel RTOS port for RX core
;
; Copyright � 2011 Maxim Salov
; All rights reserved.
;
; Assembler:   GCC
;
; Permission to use, copy, modify, and distribute this software in source
; and binary forms and its documentation for any purpose and without fee
; is hereby granted, provided that the above copyright notice appear
; in all copies and that both that copyright notice and this permission
; notice appear in supporting documentation.
;
; THIS SOFTWARE IS PROVIDED BY THE YURI TIOMKIN AND CONTRIBUTORS "AS IS" AND
; ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
; ARE DISCLAIMED. IN NO EVENT SHALL YURI TIOMKIN OR CONTRIBUTORS BE LIABLE
; FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
; DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
; OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
; HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
; LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
; OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
; SUCH DAMAGE.
; -----------------------------------------------------------------------------

	.section .text

	;; External references
	
	.extern   _tn_curr_run_task
	.extern   _tn_next_task_to_run
	.extern   _tn_system_state
	.extern   __stack
	.extern	  __isr_vectors
	.extern	  _sci2_puts
	.extern	  _sci2_putchar
	.extern	  _sci2_puthex4

	;; Public functions declared in this file

	.global	 _tn_startup_hardware_init
	.global	 _tn_startup
	.global  _tn_switch_context
	.global  _tn_switch_context_exit
	.global  _tn_switch_context_irq_handler
	.global  _tn_trap_cpu_save_sr
	.global  _tn_trap_cpu_restore_sr
	.global  _tn_icpu_save_sr
	.global  _tn_icpu_restore_sr
	.global  _tn_cpu_save_sr
	.global  _tn_cpu_restore_sr
	.global  _tn_start_exe
	.global  _tn_chk_irq_disabled
	.global  _tn_int_exit
	.global	 _tn_cpu_int_enable
	.global	 _tn_inside_int

	;; Addresses and bits for SWINT
	
	.equ	SWINTR,		0x000872E0
	.equ	SWINT,		1
	.equ	IPR03,		0x00087303
	.equ	SWINTPR,	1
	.equ	IER03,		0x00087203
	.equ	IEN3,		3
	.equ	IR027,		0x0008701B
	.equ	SWINTVECTOR,	27

	.equ	TN_ST_STATE_RUNNING,	1
	
	;; Bit definitions fo PSW register
	
	.equ	I_BIT_N,	16
	.equ	I_BIT,		(1 << I_BIT_N)
	.equ	U_BIT_N,	17
	.equ	U_BIT,		(1 << U_BIT_N)
	.equ	PM_BIT_N,	20
	.equ	PM_BIT,		(1 << PM_BIT_N)
	.equ	IPL_BITS,	0x0F000000

	;; Trap numbers
	
	.equ	TRAP_SAVE_SR,		10
	.equ	TRAP_RESTORE_SR,	11

	.equ	ENDL,		0x0A

/* ------------------------------------------------------------------------ */

_tn_startup_hardware_init:

	rts

/* ------------------------------------------------------------------------ */

_tn_startup:

	;; Set all vectors to dummy isr handler
	mvfc	intb, r1
	mov.l	#_tn_dummy_isr, r2
	mov.l	#256, r3
_tn_startup_loop:
	mov.l	r2, [r1+]
	sub	#1, r3
	bnz	_tn_startup_loop

	;; Configure vectors for used unconditional traps and interrupts
	mvfc	intb, r1
	mov.l	#_tn_switch_context_irq_handler, SWINTVECTOR*4[r1]
	mov.l	#_tn_trap_cpu_save_sr, TRAP_SAVE_SR*4[r1]
	mov.l	#_tn_trap_cpu_restore_sr, TRAP_RESTORE_SR*4[r1]

	;; Enable SWINT (software interrupt), which is used to switch context
	mov.l	#IER03, r1
	mov.l	#IPR03, r2
 	mov.l	#IR027, r3
	bclr	#IEN3, [r1].b				    ; Disable SWINT
	mov.b	#SWINTPR, [r2]				    ; Set SWINT priority to lowest
	mov.b	#0, [r3]				    ; Reset interrupt request
	bset	#IEN3, [r1].b				    ; Enable SWINT

	rts

/* ------------------------------------------------------------------------ */

.if 1
_tn_dummy_isr_msg:
	.asciz	"Dummy ISR handler.\n"
.endif
_tn_dummy_isr:
.if 1
	mov.l	#_tn_dummy_isr_msg, r1
	bsr	_sci2_puts
.endif
.if 1
	;; Print pointer to destination function
	mov.l	#tn_func_msg, r1
	bsr	_sci2_puts
	mov.l	0[r0], r1
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
	;; Print PSW
	mov.l	#tn_psw_msg, r1
	bsr	_sci2_puts
	mov.l	4[r0], r1
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
	;; Print USP
	mov.l	#tn_usp_msg, r1
	bsr	_sci2_puts
	mvfc	usp, r1
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
.endif
.if 1
	bra.b	.
.endif
	rte

/* ------------------------------------------------------------------------ */

.if 1
tn_context_msg:	
	.asciz	"* Context :\n"
tn_context_reg_msg:	
	.asciz	"** "

;; Print context macro
.macro _tn_print_context
	mov.l	#tn_context_msg, r1
	bsr.a	_sci2_puts
	;; R6 - pointer to stack
	;; R7 - index for counting
	mov.l	r0, r6
	mov.l	#15, r7
_tn_print_context\@:
	mov.l	#tn_context_reg_msg, r1
	bsr.a	_sci2_puts
	mov.l	[r6+], r1
	bsr.a	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr.a	_sci2_putchar
	sub	#1, r7
	bnz	_tn_print_context\@
.endm
.endif

/* ------------------------------------------------------------------------ */
.if 1
tn_psw_msg:	
	.asciz	"psw  : "
tn_func_msg:	
	.asciz	"func : "
tn_usp_msg:	
	.asciz	"usp  : "
tn_start_exe_exit_msg:	
	.asciz	"leaving tn_start_exe\n"
.endif

_tn_start_exe:

	;; Interrupts must be disabled for now, but we should not trust user :/
	clrpsw	I

	;; Set system state to TN_ST_STATE_RUNNING
	mov.l	#_tn_system_state, r1
	mov.l	#TN_ST_STATE_RUNNING, [r1]

	;; Make request for context switch
	;; bsr	_tn_switch_context

	;; Reset interrupt stack pointer into initial state
	mov.l	#__stack, r1
	mvtc	r1, isp

	;; Prepare for first context switch
	;; Read current task pointer and write it to USP (user stack pointer)
	mov.l	#_tn_curr_run_task, r1
	mov.l	[r1], r1
	mov.l	[r1], r1
	mvtc	r1, usp
	
	;; Restore PC and PSW from user stack and place it into interrupt stack
	setpsw	U
	popm	r1-r2
	clrpsw	U
	;; or	#I_BIT|U_BIT|PM_BIT, r2			    ; Ensure that task will run in user mode with enabled interrupts (r1 contain PSW value)
	pushm	r1-r2

.if 1
	;; Print pointer to destination function
	mov.l	#tn_func_msg, r1
	bsr	_sci2_puts
	mov.l	0[r0], r1
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
	;; Print PSW
	mov.l	#tn_psw_msg, r1
	bsr	_sci2_puts
	mov.l	4[r0], r1
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
	;; Print USP
	mov.l	#tn_usp_msg, r1
	bsr	_sci2_puts
	mvfc	usp, r1
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
	
	mov.l	#tn_start_exe_exit_msg, r1
	bsr	_sci2_puts
.endif
	
	;; Read task context
	setpsw	U
.if 1
	;; Print task context
	_tn_print_context
.endif
	popm	r1-r15					    ; Restore context of new task
	;; Switch back to interrupt stack
	clrpsw	U

	;; "Return" from interrupt. This will fetch task's address and PSW value with already enabled interrupts, user mode and user stack pointer
	rte
	;; We should not reach this point
	bra.b  	.

/* ------------------------------------------------------------------------ */

_tn_switch_context_exit:

	;; Enable interrupts
	mov.l	#1, r1
	bsr	_tn_cpu_restore_sr
	;; Make request for context switch
	bsr	_tn_switch_context
	;; We should not reach this point
	bra.b  	.

/* ------------------------------------------------------------------------ */

_tn_switch_context_irq_handler_rte:

.if 1
	pushm	r1-r15
	mov.l	#tn_switch_context_no_switch_msg, r1
	bsr	_sci2_puts
	popm	r1-r15
.endif
	popm	r1-r2
	rte

.if 1
tn_switch_context_msg:	
	.asciz	"tn_switch_context_irq\n"
tn_switch_context_no_switch_msg:
	.asciz	"Curr and next tasks are the same\n"
tn_switch_msg:	
	.asciz	"-->>\n"
tn_tcb_curr_msg:	
	.asciz	"tcb_curr : "
tn_tcb_next_msg:	
	.asciz	"tcb_next : "
.endif

_tn_switch_context_irq_handler:

.if 1
	pushm	r1-r15
	mov.l	#tn_switch_context_msg, r1
	bsr	_sci2_puts
	popm	r1-r15
.endif
	;; rte

	pushm	r1-r2
	;; The context switching - to do or not to do, that is the question :)
	mov.l	#_tn_curr_run_task, r1
	mov.l	#_tn_next_task_to_run, r2
	mov.l	[r2], r2
	mov.l	[r1], r1				    ; If both poiters reference one task - not to do

.if 1
	pushm	r1-r15

	push	r2
	push	r1
	;; Print current task tcb
	mov.l	#tn_tcb_curr_msg, r1
	bsr	_sci2_puts
	pop	r1
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
	
	;; Print next task tcb
	mov.l	#tn_tcb_next_msg, r1
	bsr	_sci2_puts
	pop	r1
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
	
	popm	r1-r15
.endif
	
	cmp	r1, r2
	beq.b	_tn_switch_context_irq_handler_rte
	;; to do
	popm	r1-r2
	
	/* -------------------------------------- */

	;; Save task context
	setpsw	U					    ; Switch to the stack of previous task
	pushm	r1-r15					    ; Save context
.if 1
	;; Print task context
	_tn_print_context
.endif
	;; Save PC and PSW of current task (located on top of isp) into task stack (usp)
	clrpsw	U
	popm	r1-r2
	setpsw	U
	pushm	r1-r2

.if 1
	;; Print pointer to destination function
	mov.l	#tn_func_msg, r1
	bsr	_sci2_puts
	mov.l	0[r0], r1
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
	;; Print PSW
	mov.l	#tn_psw_msg, r1
	bsr	_sci2_puts
	mov.l	4[r0], r1
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
	;; Print USP
	mov.l	#tn_usp_msg, r1
	bsr	_sci2_puts
	mvfc	usp, r1
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
.endif

	;; Prepare to save/switch/restore stack pointers
	mov.l	#_tn_curr_run_task, r1
	mov.l	[r1], r5				    ; Read TCB address of current task
	mov.l	#_tn_next_task_to_run, r2
	mov.l	[r2], r6				    ; Read TCB address of next task
	;; Save current stack pointer
	mvfc	usp, r3
	mov.l	r3, [r5]
	;; Set next task as current one
	mov.l	r6, [r1]
	;; Restore start pointer
	mov.l	[r6], r3
	mvtc	r3, usp

	;; Restore PC and PSW from user stack and place it into interrupt stack
	setpsw	U
	popm	r1-r2
	clrpsw	U
	pushm	r1-r2

.if 1
	mov.l	#tn_switch_msg, r1
	bsr	_sci2_puts
	;; Print pointer to destination function
	mov.l	#tn_func_msg, r1
	bsr	_sci2_puts
	mov.l	0[r0], r1
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
	;; Print PSW
	mov.l	#tn_psw_msg, r1
	bsr	_sci2_puts
	mov.l	4[r0], r1
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
	;; Print USP
	mov.l	#tn_usp_msg, r1
	bsr	_sci2_puts
	mvfc	usp, r1
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
.endif

	;; Read task context
	setpsw	U
.if 1
	;; Print task context
	_tn_print_context
.endif
	popm	r1-r15					    ; Restore context of new task
	;; Switch back to interrupt stack
	clrpsw	U

	/* -------------------------------------- */

	rte

/* ------------------------------------------------------------------------ */

_tn_switch_context:
_tn_int_exit:

	mov.l	#SWINTR, r1
	mov.b	#SWINT, [r1]				    ; Trigger software interrupt
	rts

/* ------------------------------------------------------------------------ */
.if 0
_tn_trap_save_msg:
	.asciz	"TRAP_SAVE_SR\n"
.endif

_tn_trap_cpu_save_sr:

.if 0
	pushm	r1-r15
	mov.l	#_tn_trap_save_msg, r1
	bsr	_sci2_puts
	popm	r1-r15
.endif
	
	push.l	r2

	mov.l	8[r0], r2		    		    ; Read PSW value from stack
	mov.l	r2, r1
	bclr	#I_BIT_N, r2				    ; Reset I bit in saved PSW
	mov.l	r2, 8[r0]				    ; Store PSW value to stack

.if 0
	pushm	r1-r15
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
	popm	r1-r15
.endif
	
	and	#I_BIT, r1				    ; Isolate I bit

	pop	r2

.if 0
	pushm	r1-r15
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
	popm	r1-r15
.endif

	rte

/* ------------------------------------------------------------------------ */
.if 0
_tn_trap_restore_msg:
	.asciz	"TRAP_RESTORE_SR\n"
.endif

_tn_trap_cpu_restore_sr:

.if 0
	pushm	r1-r15
	mov.l	#_tn_trap_restore_msg, r1
	bsr	_sci2_puts
	popm	r1-r15
.endif

.if 0
	pushm	r1-r15
	bsr	_sci2_puthex4
	mov.l	#ENDL, r1
	bsr	_sci2_putchar
	popm	r1-r15
.endif
	
	push.l	r2

	mov.l	8[r0], r2		    		    ; Read PSW value from stack
	cmp	#0, r1					    ; Check if we need to set I bit
	bmnz	#I_BIT_N, r2				    ; Enable/disable interrupts in saved PSW
	mov.l	r2, 8[r0]				    ; Store PSW value to stack

	pop	r2
	rte

/* ------------------------------------------------------------------------ */

_tn_cpu_save_sr:

	int	#TRAP_SAVE_SR
	rts

/* ------------------------------------------------------------------------ */

_tn_cpu_restore_sr:

	int	#TRAP_RESTORE_SR
	rts

/* ------------------------------------------------------------------------ */

_tn_icpu_save_sr:

	mvfc	psw, r1
	clrpsw	I
	and	#I_BIT, r1
	rts

/* ------------------------------------------------------------------------ */

_tn_icpu_restore_sr:

	mvfc	psw, r2
	cmp	#0, r1
	bmnz	#I_BIT_N, r2
	mvtc	r2, psw
	rts

/* ------------------------------------------------------------------------ */

_tn_chk_irq_disabled:

	mvfc	psw, r1
	and	#I_BIT, r1				    ; Isolate I bit
	bnot	#I_BIT_N, r1				    ; Invert I bit
	rts

/* ------------------------------------------------------------------------ */

_tn_cpu_int_enable:
	;; This function is invoked as a starting point of tn_timer_task_func.
	;; But interrupts are already enabled, because the only way there -- to
	;; perform context switch, that is done in SWINT.

	;; But lets implement it any way
	mov.l	#1, r1
	bsr	_tn_cpu_restore_sr
	rts

/* ------------------------------------------------------------------------ */

_tn_inside_int:

	mvfc	psw, r1
	and	#IPL_BITS, r1
	rts

/* ------------------------------------------------------------------------ */

	.end
