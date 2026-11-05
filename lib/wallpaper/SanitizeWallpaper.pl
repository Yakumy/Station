#!/usr/bin/perl

use strict;
use warnings;
use Fcntl qw(O_CREAT O_EXCL O_NOFOLLOW O_RDONLY O_WRONLY);
use POSIX qw(S_ISDIR S_ISREG);

use constant MAX_INPUT_BYTES => 128 * 1024 * 1024;
use constant MAX_PNG_CHUNKS => 4096;
use constant MAX_RASTER_BYTES => 256 * 1024 * 1024;

sub fail {
    die "$_[0]\n";
}

sub read_exact {
    my ($handle, $length) = @_;
    my $buffer = '';
    while (length($buffer) < $length) {
        my $read = sysread($handle, $buffer, $length - length($buffer), length($buffer));
        fail('could not read image') unless defined $read;
        fail('truncated image') if $read == 0;
    }
    return $buffer;
}

sub write_all {
    my ($handle, $buffer) = @_;
    my $offset = 0;
    while ($offset < length($buffer)) {
        my $written = syswrite($handle, $buffer, length($buffer) - $offset, $offset);
        fail('could not write sanitized image') unless defined $written && $written > 0;
        $offset += $written;
    }
}

sub transfer_exact {
    my ($input, $output, $length, $keep) = @_;
    while ($length > 0) {
        my $part = $length > 64 * 1024 ? 64 * 1024 : $length;
        my $buffer = read_exact($input, $part);
        write_all($output, $buffer) if $keep;
        $length -= $part;
    }
}

sub png_raster_bytes {
    my ($width, $height, $depth, $colour) = @_;
    my %valid = (
        0 => { 1 => 1, 2 => 1, 4 => 1, 8 => 1, 16 => 1 },
        2 => { 8 => 1, 16 => 1 },
        3 => { 1 => 1, 2 => 1, 4 => 1, 8 => 1 },
        4 => { 8 => 1, 16 => 1 },
        6 => { 8 => 1, 16 => 1 },
    );
    fail('invalid PNG colour format') unless $valid{$colour} && $valid{$colour}{$depth};
    my $bytes_per_pixel = $depth == 16 && $colour != 0 && $colour != 3 ? 8 : 4;
    fail('PNG dimensions exceed the raster budget')
        if $width == 0 || $height == 0
        || $width > int(MAX_RASTER_BYTES / $bytes_per_pixel)
        || $height > int(MAX_RASTER_BYTES / $bytes_per_pixel)
        || $width * $height > int(MAX_RASTER_BYTES / $bytes_per_pixel);
}

sub sanitize_png {
    my ($input, $output, $size) = @_;
    my $signature = read_exact($input, 8);
    fail('invalid PNG signature') unless $signature eq "\x89PNG\r\n\x1a\n";
    write_all($output, $signature);

    my %kept_ancillary = map { $_ => 1 } qw(PLTE tRNS cHRM gAMA sRGB pHYs sBIT bKGD);
    my %maximum_length = (
        IHDR => 13, PLTE => 768, tRNS => 256, cHRM => 32, gAMA => 4,
        sRGB => 1, pHYs => 9, sBIT => 4, bKGD => 6, IEND => 0,
    );
    my ($chunks, $consumed, $saw_header, $saw_data, $saw_end) = (0, 8, 0, 0, 0);

    while (!$saw_end) {
        fail('too many PNG chunks') if ++$chunks > MAX_PNG_CHUNKS;
        my $header = read_exact($input, 8);
        $consumed += 8;
        my ($length, $type) = unpack('Na4', $header);
        fail('invalid PNG chunk type') unless $type =~ /\A[A-Za-z]{4}\z/;
        fail('PNG chunk exceeds the input budget') if $length > MAX_INPUT_BYTES;
        fail('PNG exceeds the input budget') if $consumed + $length + 4 > $size;

        fail('IHDR must be the first PNG chunk') if !$saw_header && $type ne 'IHDR';
        fail('duplicate PNG header') if $type eq 'IHDR' && $saw_header;
        fail('unknown critical PNG chunk')
            if substr($type, 0, 1) =~ /[A-Z]/ && $type !~ /\A(?:IHDR|PLTE|IDAT|IEND)\z/;

        my $keep = $type =~ /\A(?:IHDR|IDAT|IEND)\z/ || $kept_ancillary{$type};
        if (exists $maximum_length{$type} && $length > $maximum_length{$type}) {
            fail("invalid $type chunk length");
        }

        write_all($output, $header) if $keep;
        if ($type eq 'IHDR') {
            my $data = read_exact($input, $length);
            my ($width, $height, $depth, $colour) = unpack('NNCC', $data);
            png_raster_bytes($width, $height, $depth, $colour);
            write_all($output, $data);
            $saw_header = 1;
        } else {
            transfer_exact($input, $output, $length, $keep);
        }

        my $crc = read_exact($input, 4);
        write_all($output, $crc) if $keep;
        $consumed += $length + 4;
        $saw_data = 1 if $type eq 'IDAT';
        if ($type eq 'IEND') {
            fail('PNG has no image data') unless $saw_data;
            $saw_end = 1;
        }
    }
    fail('trailing data after PNG end') unless $consumed == $size;
}

@ARGV == 2 or fail('usage: SanitizeWallpaper.pl SOURCE DESTINATION_DIRECTORY');
my ($source, $directory) = @ARGV;
fail('source must be an absolute local path') unless $source =~ m{\A/} && $source !~ /[\x00-\x1f\x7f]/;
fail('destination must be an absolute local path') unless $directory =~ m{\A/} && $directory !~ /[\x00-\x1f\x7f]/;

sysopen(my $input, $source, O_RDONLY | O_NOFOLLOW) or fail('could not open image');
binmode($input);
my @stat = stat($input);
fail('image must be a regular file') unless @stat && S_ISREG($stat[2]);
my $size = $stat[7];
fail('image is empty or exceeds the input budget') if $size <= 0 || $size > MAX_INPUT_BYTES;

my $prefix = read_exact($input, $size < 12 ? $size : 12);
sysseek($input, 0, 0) or fail('could not rewind image');
my ($format, $extension);
if (substr($prefix, 0, 8) eq "\x89PNG\r\n\x1a\n") {
    ($format, $extension) = ('png', 'png');
} elsif (substr($prefix, 0, 3) eq "\xff\xd8\xff") {
    ($format, $extension) = ('copy', 'jpg');
} elsif (substr($prefix, 0, 6) eq 'GIF87a' || substr($prefix, 0, 6) eq 'GIF89a') {
    ($format, $extension) = ('copy', 'gif');
} elsif (substr($prefix, 0, 2) eq 'BM') {
    ($format, $extension) = ('copy', 'bmp');
} elsif (length($prefix) >= 12 && substr($prefix, 0, 4) eq 'RIFF' && substr($prefix, 8, 4) eq 'WEBP') {
    ($format, $extension) = ('copy', 'webp');
} else {
    fail('unsupported image format');
}

my $parent = $directory;
$parent =~ s{/[^/]+\z}{};
fail('invalid destination directory') unless length($parent) > 1;
if (!-e $parent) {
    mkdir($parent, 0700) or fail('could not create private wallpaper parent');
}
my @parent_stat = lstat($parent);
fail('private wallpaper parent must be a real directory')
    unless @parent_stat && S_ISDIR($parent_stat[2]) && !-l _;
mkdir($directory, 0700) or fail('could not create private wallpaper directory');
my $destination = "$directory/image.$extension";
my $ok = eval {
    sysopen(my $output, $destination, O_WRONLY | O_CREAT | O_EXCL, 0600)
        or fail('could not create sanitized image');
    binmode($output);
    if ($format eq 'png') {
        sanitize_png($input, $output, $size);
    } else {
        transfer_exact($input, $output, $size, 1);
    }
    close($output) or fail('could not finish sanitized image');
    close($input) or fail('could not finish reading image');
    1;
};
if (!$ok) {
    my $error = $@ || "could not sanitize image\n";
    unlink($destination);
    rmdir($directory);
    die $error;
}

print "$destination\n";
