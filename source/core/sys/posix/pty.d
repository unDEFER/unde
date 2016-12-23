module core.sys.posix.pty;

import core.sys.posix.sys.ioctl;
import core.sys.posix.termios;

extern(C)
{
version(Posix)
{
   
/* Create pseudo tty master slave pair with NAME and set terminal
   attributes according to TERMP and WINP and return handles for both
   ends in AMASTER and ASLAVE.  */
int openpty (int *__amaster, int *__aslave, char *__name,
            const termios *__termp,
            const winsize *__winp);

/* Create child process and establish the slave pseudo terminal as the
      child's controlling terminal.  */
int forkpty (int *__amaster, char *__name,
        const termios *__termp,
        const winsize *__winp);

}
}

