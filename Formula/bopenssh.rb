class Bopenssh < Formula
  desc "OpenBSD freely-licensed SSH connectivity tools"
  homepage "https://www.openssh.com/"
  url "https://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-7.4p1.tar.gz"
  mirror "https://www.mirrorservice.org/pub/OpenBSD/OpenSSH/portable/openssh-7.4p1.tar.gz"
  version "7.4p1"
  sha256 "1b1fc4a14e2024293181924ed24872e6f2e06293f3e8926a376b8aec481f19d1"
  revision 1

  depends_on "pkg-config" => :build
  depends_on "libressl"
  depends_on "ldns" => :optional

  # Both these patches are applied by Apple.
  patch do
    url "https://raw.githubusercontent.com/Homebrew/patches/1860b0a74/openssh/patch-sandbox-darwin.c-apple-sandbox-named-external.diff"
    sha256 "d886b98f99fd27e3157b02b5b57f3fb49f43fd33806195970d4567f12be66e71"
  end

  patch do
    url "https://raw.githubusercontent.com/Homebrew/patches/d8b2d8c2/openssh/patch-sshd.c-apple-sandbox-named-external.diff"
    sha256 "3505c58bf1e584c8af92d916fe5f3f1899a6b15cc64a00ddece1dc0874b2f78f"
  end

  # Patch for SSH tunnelling issues caused by launchd changes on Yosemite
  patch do
    url "https://raw.githubusercontent.com/Homebrew/patches/d8b2d8c2/OpenSSH/launchd.patch"
    sha256 "df61404042385f2491dd7389c83c3ae827bf3997b1640252b018f9230eab3db3"
  end

  def install
    ENV.append "CPPFLAGS", "-D__APPLE_SANDBOX_NAMED_EXTERNAL__"

    # Ensure sandbox profile prefix is correct.
    inreplace "sandbox-darwin.c", "@PREFIX@/share/openssh", etc/"ssh"

    args = %W[
      --with-libedit
      --with-pam
      --with-kerberos5
      --prefix=#{prefix}
      --sysconfdir=#{etc}/ssh
      --with-ssl-dir=#{Formula["libressl"].opt_prefix}
    ]

    args << "--with-ldns" if build.with? "ldns"

    system "./configure", *args
    system "make"
    system "make", "install"

    # This was removed by upstream with very little announcement and has
    # potential to break scripts, so recreate it for now.
    # Debian have done the same thing.
    bin.install_symlink bin/"ssh" => "slogin"

    # https://opensource.apple.com/source/OpenSSH/OpenSSH-209.30.4/com.openssh.sshd.sb
    (buildpath/"org.openssh.sshd.sb").write <<-EOS.undent
      ;; Copyright (c) 2008 Apple Inc.  All Rights reserved.
      ;;
      ;; sshd - profile for privilege separated children
      ;;
      ;; WARNING: The sandbox rules in this file currently constitute
      ;; Apple System Private Interface and are subject to change at any time and
      ;; without notice.
      ;;

      (version 1)

      (deny default)

      (allow file-chroot)
      (allow file-read-metadata (literal "/var"))

      (allow sysctl-read)
      (allow mach-per-user-lookup)
      (allow mach-lookup
      	(global-name "com.apple.system.notification_center")
      	(global-name "com.apple.system.opendirectoryd.libinfo")
      	(global-name "com.apple.system.opendirectoryd.libinfo") ;; duplicate name as a work-around for 19978803
      	(global-name "com.apple.system.logger"))
    EOS
    (etc/"ssh").install "org.openssh.sshd.sb"
  end
end
