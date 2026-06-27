# ===================== S3 buckets =====================
resource "aws_s3_bucket" "dc" {
  bucket = var.dc_bucket_name
  tags   = { Name = "${var.name_prefix}-s3-dc" }
}

resource "aws_s3_bucket" "dr" {
  provider = aws.dr
  bucket   = var.dr_bucket_name
  tags     = { Name = "${var.name_prefix}-s3-dr" }
}

# Versioning (required for replication)
resource "aws_s3_bucket_versioning" "dc" {
  bucket = aws_s3_bucket.dc.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_versioning" "dr" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr.id
  versioning_configuration { status = "Enabled" }
}

# ===================== Replication IAM role =====================
data "aws_iam_policy_document" "replication_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  name               = "${var.name_prefix}-s3-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_assume.json
}

data "aws_iam_policy_document" "replication" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [aws_s3_bucket.dc.arn, aws_s3_bucket.dr.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
    resources = ["${aws_s3_bucket.dc.arn}/*", "${aws_s3_bucket.dr.arn}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
    resources = ["${aws_s3_bucket.dc.arn}/*", "${aws_s3_bucket.dr.arn}/*"]
  }
}

resource "aws_iam_role_policy" "replication" {
  name   = "${var.name_prefix}-s3-replication"
  role   = aws_iam_role.replication.id
  policy = data.aws_iam_policy_document.replication.json
}

# ===================== Replication rules (disjoint prefixes) =====================
# DC bucket  dc/  --->  DR bucket   (active, normal direction)
resource "aws_s3_bucket_replication_configuration" "dc_to_dr" {
  depends_on = [aws_s3_bucket_versioning.dc, aws_s3_bucket_versioning.dr]
  role       = aws_iam_role.replication.arn
  bucket     = aws_s3_bucket.dc.id

  rule {
    id     = "dc-prefix-to-dr"
    status = "Enabled"
    filter { prefix = "dc/" }
    delete_marker_replication { status = "Disabled" }
    destination { bucket = aws_s3_bucket.dr.arn }
  }
}

# DR bucket  dr/  --->  DC bucket   (dormant until failover; only dr/ flows back)
resource "aws_s3_bucket_replication_configuration" "dr_to_dc" {
  provider   = aws.dr
  depends_on = [aws_s3_bucket_versioning.dc, aws_s3_bucket_versioning.dr]
  role       = aws_iam_role.replication.arn
  bucket     = aws_s3_bucket.dr.id

  rule {
    id     = "dr-prefix-to-dc"
    status = "Enabled"
    filter { prefix = "dr/" }
    delete_marker_replication { status = "Disabled" }
    destination { bucket = aws_s3_bucket.dc.arn }
  }
}
