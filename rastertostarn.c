/*
 * rastertostarn.c - native CUPS raster filter for the Star TSP143 receipt
 * printer (original TSP100 series) in raster mode ("Star Graphic Mode").
 *
 * Why: the vendor's macOS driver for the original TSP100 ships Intel-only
 * (x86_64) filters, which need Rosetta 2 on Apple Silicon. This filter does
 * the same job as a universal binary (arm64 and x86_64) and depends on
 * nothing but the CUPS library that comes with macOS.
 *
 * What it does: reads CUPS raster (1 bit per pixel; 8-bit grey is accepted
 * too and thresholded at mid-scale) and writes the printer commands to
 * stdout. The sequence below was worked out by running the vendor's legacy
 * filter by hand on test pages, with its output captured to a file, and
 * matching that output byte for byte (see test.sh). No vendor source code
 * was read.
 *
 *   job:   ESC @                     reset the printer
 *          ESC RS A n                print area: 0 = 72 mm; 1 = 50.8 mm, only with the
 *                                    "X50D8MM..." page sizes (a custom size always gives 0)
 *          ESC BEL n1 n2             cash drawer pulse: n1 x 10 ms on, n2 x 10 ms off
 *          ESC * r R, ESC * r A      reset raster mode and enter it
 *          ESC * r Q q NUL           speed: 0 high, 1 medium, 2 low
 *          ESC * r D d NUL           cash drawer: 0 leave closed, 1 to 3 open
 *          ESC * r P 0 NUL           variable page length (sent only in that case)
 *          ESC * r F f NUL           end of page: 1 no cut, 13 partial cut
 *          ESC * r E e NUL           end of document: 1 no cut, 13 partial cut
 *   page:  NUL
 *          ESC * r P h+1 NUL         fixed page length, in lines (sent only in that case)
 *          ESC * r Y n NUL           skip n blank lines (trailing blank lines are not sent)
 *          b nL nH data              one line of dots: 1 = black, most significant bit on the left
 *          ESC * r Y 1 NUL, ESC FF   end of page
 *   end:   EOT, ESC * r B            end of document (this is where it cuts), leave raster mode
 *
 * Usage (as CUPS runs it): rastertostarn job user title copies options [file]
 * Options, as named in the PPD: PrintSpeed, PageType, PageCutType, DocCutType,
 * CashDrawerSetting, CashDrawer1PulseWidth. Without a PPD (run by hand) they
 * are read from the fifth argument ("PrintSpeed=2Low DocCutType=0NoCutDoc").
 *
 * Cancelling: SIGTERM is handled with SA_RESTART, so a write in progress
 * resumes and the page and the document are always closed. Without it, a job
 * cancelled while the filter is blocked writing would stop in the middle of a
 * line of dots; the printer would wait for the rest and swallow the start of
 * the next job. The final flush is checked (it carries the cut), and a raster
 * stream that ends early because the job was cancelled is not an error.
 *
 * Build: ./build.sh
 *
 * SPDX-License-Identifier: MIT
 */
#include <cups/cups.h>
#include <cups/ppd.h>
#include <cups/raster.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define VERSION        "1.1.0"
#define MAX_LINE_BYTES 72           /* 576 dots: the width of the print head */

static volatile sig_atomic_t cancelled = 0;

static void on_cancel(int sig)
{
    (void)sig;
    cancelled = 1;
}

static void put(const void *data, size_t n)
{
    if (n && fwrite(data, 1, n, stdout) != n) {
        fputs("ERROR: could not write to the printer\n", stderr);
        exit(1);
    }
}

/* ESC * r <letter> <value in digits> NUL */
static void command(char letter, unsigned value)
{
    char b[32];
    int n = snprintf(b, sizeof b, "\033*r%c%u", letter, value);
    put(b, (size_t)n + 1);          /* + 1: the NUL that ends the value */
}

/* The choice of an option: the one marked in the PPD; without a PPD, the one
 * given in the job options; otherwise NULL. */
static const char *choice_text(ppd_file_t *ppd, int num_options, cups_option_t *options, const char *name)
{
    if (ppd) {
        ppd_choice_t *c = ppdFindMarkedChoice(ppd, name);
        if (c) return c->choice;
    }
    return cupsGetOption(name, num_options, options);
}

/* The number a choice starts with ("2Low" -> 2); `fallback` if there is none. */
static int choice_number(ppd_file_t *ppd, int num_options, cups_option_t *options, const char *name, int fallback)
{
    const char *v = choice_text(ppd, num_options, options, name);
    if (!v || v[0] < '0' || v[0] > '9') return fallback;
    return atoi(v);
}

int main(int argc, char *argv[])
{
    if (argc < 6 || argc > 7) {
        fprintf(stderr, "rastertostarn %s\nUsage: %s job user title copies options [file]\n", VERSION, argv[0]);
        return 1;
    }
    int fd = 0;
    if (argc == 7 && (fd = open(argv[6], O_RDONLY)) < 0) {
        perror("ERROR: could not open the raster file");
        return 1;
    }

    cups_option_t *options = NULL;
    int num_options = cupsParseOptions(argv[5], 0, &options);
    const char *ppd_path = getenv("PPD");
    ppd_file_t *ppd = ppd_path ? ppdOpenFile(ppd_path) : NULL;
    if (ppd) {
        ppdMarkDefaults(ppd);
        cupsMarkOptions(ppd, num_options, options);
    }
    int speed      = choice_number(ppd, num_options, options, "PrintSpeed", 0);
    int fixed_page = choice_number(ppd, num_options, options, "PageType", 0) == 1;
    int page_cut   = choice_number(ppd, num_options, options, "PageCutType", 0);
    int doc_cut    = choice_number(ppd, num_options, options, "DocCutType", 1);
    int drawer     = choice_number(ppd, num_options, options, "CashDrawerSetting", 0);
    int pulse      = choice_number(ppd, num_options, options, "CashDrawer1PulseWidth", 2);
    if (speed < 0 || speed > 2) speed = 0;
    if (drawer < 0 || drawer > 3) drawer = 0;
    if (pulse < 0 || pulse > 12) pulse = 2;
    /* Narrow paper (50.8 mm print area): only for the page sizes with that name, as in the vendor's filter. */
    const char *page_size = choice_text(ppd, num_options, options, "PageSize");
    int narrow = page_size && strncmp(page_size, "X50D8MM", 7) == 0;

    cups_raster_t *ras = cupsRasterOpen(fd, CUPS_RASTER_READ);
    if (!ras) {
        fputs("ERROR: the input is not CUPS raster\n", stderr);
        return 1;
    }
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_cancel;
    sa.sa_flags = SA_RESTART;       /* a write in progress resumes: the page and the document are always closed */
    sigaction(SIGTERM, &sa, NULL);

    cups_page_header2_t h;
    unsigned char *line = NULL, out[MAX_LINE_BYTES];
    int pages = 0, header_sent = 0, failed = 0;

    for (;;) {
        int have_page = !cancelled && !failed && cupsRasterReadHeader2(ras, &h);
        if (!header_sent) {
            /* The job header is always sent, even with no pages, as the vendor's filter does. */
            unsigned char start[] = {
                0x1b, '@',
                0x1b, 0x1e, 'A', (unsigned char)narrow,
                0x1b, 0x07, (unsigned char)(pulse == 0 ? 1 : pulse * 10), 20,
                0x1b, '*', 'r', 'R',
                0x1b, '*', 'r', 'A',
            };
            put(start, sizeof start);
            command('Q', (unsigned)speed);
            command('D', (unsigned)drawer);
            if (!fixed_page) command('P', 0);
            command('F', page_cut == 1 ? 13 : 1);
            command('E', doc_cut == 1 ? 13 : 1);
            header_sent = 1;
        }
        if (!have_page) break;

        int bits = (int)h.cupsBitsPerPixel;
        int white_is_zero;          /* in the raster, is paper (white) the value 0? */
        if (h.cupsColorSpace == CUPS_CSPACE_K) white_is_zero = 1;
        else if (h.cupsColorSpace == CUPS_CSPACE_W || h.cupsColorSpace == CUPS_CSPACE_SW) white_is_zero = 0;
        else {
            fprintf(stderr, "ERROR: raster colour space %u is not supported (black or grey only)\n", h.cupsColorSpace);
            failed = 1;
            continue;
        }
        if ((bits != 1 && bits != 8) || h.cupsBytesPerLine == 0 || h.cupsBytesPerLine > 65535 ||
            (bits == 8 && h.cupsBytesPerLine < h.cupsWidth) ||
            (bits == 1 && h.cupsBytesPerLine < (h.cupsWidth + 7) / 8)) {
            fprintf(stderr, "ERROR: raster with %d bits, %u bytes per line and %u dots is not supported\n",
                    bits, h.cupsBytesPerLine, h.cupsWidth);
            failed = 1;
            continue;
        }
        unsigned char *grown = realloc(line, h.cupsBytesPerLine);
        if (!grown) {
            fputs("ERROR: out of memory\n", stderr);
            failed = 1;
            continue;
        }
        line = grown;
        /* Bytes sent per line: those of 1-bit raster as they come; never more than the print head. */
        size_t out_bytes = bits == 1 ? h.cupsBytesPerLine : (h.cupsWidth + 7) / 8;
        if (out_bytes > MAX_LINE_BYTES) out_bytes = MAX_LINE_BYTES;
        unsigned dots = h.cupsWidth < out_bytes * 8 ? h.cupsWidth : (unsigned)(out_bytes * 8);

        pages++;
        fprintf(stderr, "INFO: Printing page %d\n", pages);
        fprintf(stderr, "DEBUG: rastertostarn %s: %ux%u dots, %d bit(s), %u bytes per line\n",
                VERSION, h.cupsWidth, h.cupsHeight, bits, h.cupsBytesPerLine);
        put("", 1);                                     /* NUL: start of page */
        if (fixed_page) command('P', h.cupsHeight + 1);

        unsigned blank = 0;
        for (unsigned y = 0; y < h.cupsHeight && !cancelled; y++) {
            if (cupsRasterReadPixels(ras, line, h.cupsBytesPerLine) != h.cupsBytesPerLine) {
                if (!cancelled) {   /* on a cancel, cupsd also stops whoever feeds us the raster */
                    fputs("ERROR: the raster ended in the middle of a page\n", stderr);
                    failed = 1;
                }
                break;
            }
            const unsigned char *d = line;
            if (bits == 8) {
                memset(out, 0, out_bytes);
                for (unsigned x = 0; x < dots; x++) {
                    int black = white_is_zero ? line[x] >= 128 : line[x] < 128;
                    if (black) out[x >> 3] |= (unsigned char)(0x80 >> (x & 7));
                }
                d = out;
            } else if (!white_is_zero) {                /* 1 bit where 1 is white: invert */
                memset(out, 0, out_bytes);
                for (unsigned x = 0; x < dots; x++)
                    if (!(line[x >> 3] & (0x80 >> (x & 7)))) out[x >> 3] |= (unsigned char)(0x80 >> (x & 7));
                d = out;
            }
            size_t n = out_bytes;                       /* trailing zero bytes of a line are not sent */
            while (n > 0 && d[n - 1] == 0) n--;
            if (n == 0) {                               /* blank line: counted with the ones that follow */
                blank++;
                continue;
            }
            if (blank) {
                command('Y', blank);
                blank = 0;
            }
            unsigned char head[3] = {'b', (unsigned char)(n & 0xff), (unsigned char)(n >> 8)};
            put(head, 3);
            put(d, n);
        }
        command('Y', 1);
        put("\033\014", 2);                             /* ESC FF: end of page */
    }

    put("\004", 1);                                     /* EOT: end of document */
    put("\033*rB", 4);                                  /* leave raster mode */
    if (fflush(stdout) != 0) {                          /* this flush is the one that carries the cut */
        fputs("ERROR: could not write the end of the document to the printer\n", stderr);
        failed = 1;
    }

    free(line);
    cupsRasterClose(ras);
    if (ppd) ppdClose(ppd);
    cupsFreeOptions(num_options, options);
    if (fd > 0) close(fd);
    if (!failed) fprintf(stderr, cancelled ? "INFO: job cancelled on page %d; page and document closed\n"
                                           : "INFO: %d page(s) sent\n", pages);
    return failed ? 1 : 0;
}
