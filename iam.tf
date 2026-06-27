# IAM user that PostgreSQL / pgBackRest will use to read+write WAL archives
resource "aws_iam_user" "pgbackrest" {
  name = "${var.name_prefix}-pgbackrest"
}

resource "aws_iam_access_key" "pgbackrest" {
  user = aws_iam_user.pgbackrest.name
}

data "aws_iam_policy_document" "pgbackrest" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.dc.arn, aws_s3_bucket.dr.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.dc.arn}/*", "${aws_s3_bucket.dr.arn}/*"]
  }
}

resource "aws_iam_user_policy" "pgbackrest" {
  name   = "${var.name_prefix}-pgbackrest"
  user   = aws_iam_user.pgbackrest.name
  policy = data.aws_iam_policy_document.pgbackrest.json
}
