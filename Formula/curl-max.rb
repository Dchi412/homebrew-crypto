class CurlMax < Formula
  desc "Feature-maximised version of cURL, using OpenSSL 1.1"
  homepage "https://curl.haxx.se/"
  url "https://curl.haxx.se/download/curl-7.58.0.tar.bz2"
  mirror "http://curl.askapache.com/download/curl-7.58.0.tar.bz2"
  sha256 "1cb081f97807c01e3ed747b6e1c9fee7a01cb10048f1cd0b5f56cfe0209de731"
  revision 1

  keg_only :provided_by_macos

  depends_on "pkg-config" => :build
  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "libtool" => :build
  depends_on "cunit" => :build
  depends_on "openssl@1.1"
  depends_on "c-ares"
  depends_on "libev"
  depends_on "jansson"
  depends_on "boost"
  depends_on "libidn2"
  depends_on "libmetalink"
  depends_on "libxml2"

  needs :cxx11

  # Needed for nghttp2
  resource "libevent" do
    url "https://github.com/libevent/libevent/releases/download/release-2.1.8-stable/libevent-2.1.8-stable.tar.gz"
    sha256 "965cc5a8bb46ce4199a47e9b2c9e1cae3b137e8356ffdad6d94d3b9069b71dc2"
  end

  resource "nghttp2" do
    url "https://github.com/nghttp2/nghttp2/releases/download/v1.30.0/nghttp2-1.30.0.tar.xz"
    sha256 "089afb4c22a53f72384b71ea06194be255a8a73b50b1412589105d0e683c52ac"
  end

  resource "libssh2" do
    url "https://libssh2.org/download/libssh2-1.8.0.tar.gz"
    sha256 "39f34e2f6835f4b992cafe8625073a88e5a28ba78f83e8099610a7b3af4676d4"
  end

  def install
    vendor = libexec/"vendor"
    ENV.prepend_path "PKG_CONFIG_PATH", Formula["openssl@1.1"].opt_lib/"pkgconfig"
    ENV.prepend_path "PKG_CONFIG_PATH", vendor/"lib/pkgconfig"
    ENV.prepend_path "PATH", vendor/"bin"
    ENV.cxx11

    resource("libevent").stage do
      system "./configure", "--disable-dependency-tracking",
                            "--disable-debug-mode",
                            "--prefix=#{vendor}"
      system "make"
      system "make", "install"
    end

    resource("nghttp2").stage do
      system "./configure", "--prefix=#{vendor}",
                            "--disable-silent-rules",
                            "--enable-app",
                            "--with-boost=#{Formula["boost"].opt_prefix}",
                            "--enable-asio-lib",
                            "--disable-python-bindings"
      system "make"
      system "make", "check"
      system "make", "install"
    end

    resource("libssh2").stage do
      system "./configure", "--prefix=#{vendor}",
                            "--disable-debug",
                            "--disable-dependency-tracking",
                            "--disable-silent-rules",
                            "--disable-examples-build",
                            "--with-openssl",
                            "--with-libz",
                            "--with-libssl-prefix=#{Formula["openssl@1.1"].opt_prefix}"
      system "make", "install"
    end

    args = %W[
      --disable-debug
      --disable-dependency-tracking
      --disable-silent-rules
      --prefix=#{prefix}
      --with-libidn2
      --with-ssl=#{Formula["openssl@1.1"].opt_prefix}
      --with-ca-bundle=#{etc}/openssl@1.1/cert.pem
      --with-ca-path=#{etc}/openssl@1.1/certs
      --enable-ares=#{Formula["c-ares"].opt_prefix}
      --with-libssh2
      --without-librtmp
      --with-gssapi
      --with-libmetalink
    ]

    system "./configure", *args
    system "make", "install"
    libexec.install "lib/mk-ca-bundle.pl"

    # curl-config --libs outputs all libs, even private ones.
    # Is a known issue upstream but can cause problems when
    # third-parties try to link against curl. Can be fixed
    # with an inreplace until upstream find a happy solution.
    inreplace bin/"curl-config",
              "${CURLLIBDIR}-lcurl -lcares",
              "${CURLLIBDIR} -L#{vendor}/lib -lcurl -lcares"
  end

  test do
    # Test vendored libraries.
    (testpath/"test.c").write <<-EOS.undent
      #include <event2/event.h>

      int main()
      {
        struct event_base *base;
        base = event_base_new();
        event_base_free(base);
        return 0;
      }
    EOS
    system ENV.cc, "test.c", "-L#{libexec}/vendor/lib", "-levent", "-o", "test"
    system "./test"

    (testpath/"test2.c").write <<-EOS.undent
      #include <libssh2.h>

      int main(void)
      {
      libssh2_exit();
      return 0;
      }
    EOS

    system ENV.cc, "test2.c", "-L#{libexec}/vendor/lib", "-lssh2", "-o", "test2"
    system "./test2"

    # Test vendored executables.
    system libexec/"vendor/bin/nghttp", "-nv", "https://nghttp2.org"

    # Test IDN support.
    ENV.delete("LC_CTYPE")
    ENV["LANG"] = "en_US.UTF-8"
    system bin/"curl", "-L", "www.räksmörgås.se", "-o", "index.html"
    assert_predicate testpath/"index.html", :exist?,
                     "Failed to download IDN example site!"
    assert_match "www.xn--rksmrgs-5wao1o.se", File.read("index.html")

    # Fetch the curl tarball and see that the checksum matches.
    # This requires a network connection, but so does Homebrew in general.
    filename = (testpath/"test.tar.gz")
    system bin/"curl", "-L", stable.url, "-o", filename
    filename.verify_checksum stable.checksum

    system libexec/"mk-ca-bundle.pl", "test.pem"
    assert_predicate testpath/"test.pem", :exist?, "Failed to generate PEM!"
    assert_predicate testpath/"certdata.txt", :exist?
  end
end
