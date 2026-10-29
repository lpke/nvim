#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

static int signal_log, ignore_term;
static char term_line[80];
static size_t term_length;

static void on_term(int signal_number) {
  (void)signal_number;
  write(signal_log, term_line, term_length);
  if (!ignore_term) _exit(0);
}

int main(int argc, char **argv) {
  if (argc < 7) return 2;
  signal_log = open(argv[1], O_WRONLY | O_CREAT | O_APPEND, 0600);
  int records = open(argv[2], O_WRONLY | O_CREAT | O_APPEND, 0600);
  if (signal_log < 0 || records < 0) return 3;
  ignore_term = strcmp(argv[4], "ignore") == 0;
  term_length = (size_t)snprintf(term_line, sizeof(term_line), "%d TERM\n", getpid());
  struct sigaction action = {0};
  action.sa_handler = on_term;
  sigemptyset(&action.sa_mask);
  sigaction(SIGTERM, &action, NULL);
  char record[128];
  int length = snprintf(record, sizeof(record), "%s\t%d\t%d\n", argv[3], getpid(), getppid());
  write(records, record, (size_t)length);
  close(records);
  const char *next = argv[5];
  if (strstr(argv[0], "acp-fixture-helper") && strcmp(next, "-") == 0) {
    next = getenv("LPKE_ACP_PROCESS_CHILD");
    if (!next) return 6;
  }
  if (strcmp(next, "-") != 0) {
    pid_t child = fork();
    if (child < 0) return 4;
    if (child == 0) {
      if (argc > 7 && strstr(argv[7], "/codex-acp/")) {
        execl(next, next, argv[7], argv[1], argv[2], argv[6], NULL);
        _exit(7);
      }
      execl(next, next, argv[1], argv[2], "child", argv[4], argv[6], "-",
            argc > 7 ? argv[7] : "-", argc > 8 ? argv[8] : "-", NULL);
      _exit(5);
    }
  }
  while (1) pause();
}
