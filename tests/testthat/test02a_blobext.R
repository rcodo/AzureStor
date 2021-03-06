context("Blob client interface, extra")

tenant <- Sys.getenv("AZ_TEST_TENANT_ID")
app <- Sys.getenv("AZ_TEST_APP_ID")
password <- Sys.getenv("AZ_TEST_PASSWORD")
subscription <- Sys.getenv("AZ_TEST_SUBSCRIPTION")

if(tenant == "" || app == "" || password == "" || subscription == "")
    skip("Authentication tests skipped: ARM credentials not set")

rgname <- Sys.getenv("AZ_TEST_STORAGE_RG")
storname <- Sys.getenv("AZ_TEST_STORAGE_NOHNS")

if(rgname == "" || storname == "")
    skip("Blob client tests skipped: resource names not set")

sub <- AzureRMR::az_rm$new(tenant=tenant, app=app, password=password)$get_subscription(subscription)
stor <- sub$get_resource_group(rgname)$get_storage_account(storname)
bl <- stor$get_blob_endpoint()
options(azure_storage_progress_bar=FALSE)

write_file <- function(dir, size=1000)
{
    fname <- tempfile(tmpdir=dir)
    bytes <- openssl::rand_bytes(size)
    writeBin(bytes, fname)
    basename(fname)
}

files_identical <- function(set1, set2)
{
    all(mapply(function(f1, f2)
    {
        s1 <- file.size(f1)
        s2 <- file.size(f2)
        s1 == s2 && identical(readBin(f1, "raw", s1), readBin(f2, "raw", s2))
    }, set1, set2))
}

srcdir <- tempfile(pattern="ul")
destdir <- tempfile(pattern="dl")
destdir2 <- tempfile(pattern="dl")
destdir3 <- tempfile(pattern="dl")
destdir4 <- tempfile(pattern="dl")
dir.create(srcdir)
dir.create(file.path(srcdir, "subdir"))

srcs <- replicate(5, write_file(srcdir))
srcs_sub <- replicate(5, write_file(file.path(srcdir, "subdir")))


test_that("Blob vector multitransfer works",
{
    contname <- paste0(sample(letters, 10, TRUE), collapse="")
    cont <- create_blob_container(bl, contname)

    # test that extra args passed to nodes
    expect_error(multiupload_blob(cont, file.path(srcdir, srcs), type="AppendBlob"))

    multiupload_blob(cont, file.path(srcdir, srcs), srcs)
    multidownload_blob(cont, srcs, file.path(destdir, srcs))

    expect_identical(AzureRMR::pool_size(), 10L)
    expect_true(files_identical(file.path(srcdir, srcs), file.path(destdir, srcs)))

    # vector src needs vector dest
    expect_error(multiupload_blob(cont, file.path(srcdir, srcs), "/"))
    expect_error(multidownload_blob(cont, srcs, destdir))
})


test_that("Blob wildcard multitransfer works",
{
    contname <- paste0(sample(letters, 10, TRUE), collapse="")
    cont <- create_blob_container(bl, contname)

    multiupload_blob(cont, file.path(srcdir, "*"), "/")
    multidownload_blob(cont, "*", destdir2)

    expect_true(files_identical(file.path(srcdir, srcs), file.path(destdir2, srcs)))

    # wildcard src needs directory dest
    expect_error(multiupload_blob(cont, file.path(srcdir, "*"), srcs))
    expect_error(multidownload_blob(cont, "*", file.path(destdir2, srcs)))
})


test_that("Blob wildcard multitransfer from subdir works",
{
    contname <- paste0(sample(letters, 10, TRUE), collapse="")
    cont <- create_blob_container(bl, contname)

    multiupload_blob(cont, file.path(srcdir, "*"), "/", recursive=TRUE)
    multidownload_blob(cont, "subdir/*", destdir3)

    expect_true(files_identical(file.path(srcdir, "subdir", srcs_sub), file.path(destdir3, srcs_sub)))
})


test_that("Blob recursive wildcard multitransfer works",
{
    contname <- paste0(sample(letters, 10, TRUE), collapse="")
    cont <- create_blob_container(bl, contname)

    multiupload_blob(cont, file.path(srcdir, "*"), "/", recursive=TRUE)
    multidownload_blob(cont, "*", destdir4, recursive=TRUE)

    expect_true(files_identical(file.path(srcdir, srcs), file.path(destdir4, srcs)))

    # wildcard src needs directory dest
    expect_error(multiupload_blob(cont, file.path(srcdir, "*"), srcs))
    expect_error(multidownload_blob(cont, "*", file.path(destdir4, srcs)))
})


test_that("Default multitransfer destination works",
{
    contname <- paste0(sample(letters, 10, TRUE), collapse="")
    cont <- create_blob_container(bl, contname)

    multiupload_blob(cont, file.path(srcdir, srcs))
    multidownload_blob(cont, srcs)

    expect_true(files_identical(file.path(srcdir, srcs), srcs))
    file.remove(srcs)
})


test_that("Default multitransfer destination works with wildcard src",
{
    contname <- paste0(sample(letters, 10, TRUE), collapse="")
    cont <- create_blob_container(bl, contname)

    multiupload_blob(cont, file.path(srcdir, "subdir/*"))
    multidownload_blob(cont, "*")

    expect_true(files_identical(file.path(srcdir, "subdir", srcs_sub), srcs_sub))
    file.remove(srcs_sub)
})


test_that("Blob multicopy from URL works",
{
    contname <- paste0(sample(letters, 10, TRUE), collapse="")
    cont <- create_blob_container(bl, contname)

    fnames <- c("LICENSE", "LICENSE.md", "CONTRIBUTING.md")
    src_urls <- paste0("https://raw.githubusercontent.com/Azure/AzureStor/master/", fnames)
    origs <- paste0("../../", fnames)
    dests <- c(tempfile(), tempfile(), tempfile())

    multicopy_url_to_blob(cont, src_urls, fnames, async=FALSE)
    multidownload_blob(cont, fnames, dests)

    # use readLines to workaround GH auto-translating CRLF -> LF
    expect_true(all(mapply(function(f1, f2)
    {
        identical(readLines(f1), readLines(f2))
    }, dests, origs)))
})


teardown(
{
    conts <- list_blob_containers(bl)
    lapply(conts, delete_blob_container, confirm=FALSE)
})
