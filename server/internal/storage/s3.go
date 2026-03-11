package storage

import (
	"context"
	"fmt"
	"io"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// S3Client wraps the AWS S3 SDK for uploading and generating presigned URLs.
type S3Client interface {
	Upload(ctx context.Context, key string, body io.Reader, contentType string) (string, error)
	PresignedURL(ctx context.Context, key string, expiry time.Duration) (string, error)
}

type s3Client struct {
	client    *s3.Client
	presigner *s3.PresignClient
	bucket    string
}

// NewS3Client creates an S3 client configured for the given bucket and region.
// It uses the default AWS credential chain (env vars AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY).
func NewS3Client(ctx context.Context, bucket, region string) (S3Client, error) {
	cfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return nil, fmt.Errorf("load AWS config: %w", err)
	}
	client := s3.NewFromConfig(cfg)
	return &s3Client{
		client:    client,
		presigner: s3.NewPresignClient(client),
		bucket:    bucket,
	}, nil
}

// NewS3ClientWithCredentials creates an S3 client with explicit credentials (for testing).
func NewS3ClientWithCredentials(ctx context.Context, bucket, region, accessKey, secretKey string) (S3Client, error) {
	cfg, err := awsconfig.LoadDefaultConfig(ctx,
		awsconfig.WithRegion(region),
		awsconfig.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(accessKey, secretKey, "")),
	)
	if err != nil {
		return nil, fmt.Errorf("load AWS config: %w", err)
	}
	client := s3.NewFromConfig(cfg)
	return &s3Client{
		client:    client,
		presigner: s3.NewPresignClient(client),
		bucket:    bucket,
	}, nil
}

func (c *s3Client) Upload(ctx context.Context, key string, body io.Reader, contentType string) (string, error) {
	_, err := c.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(c.bucket),
		Key:         aws.String(key),
		Body:        body,
		ContentType: aws.String(contentType),
	})
	if err != nil {
		return "", fmt.Errorf("s3 put object: %w", err)
	}
	return key, nil
}

func (c *s3Client) PresignedURL(ctx context.Context, key string, expiry time.Duration) (string, error) {
	resp, err := c.presigner.PresignGetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(c.bucket),
		Key:    aws.String(key),
	}, s3.WithPresignExpires(expiry))
	if err != nil {
		return "", fmt.Errorf("s3 presign: %w", err)
	}
	return resp.URL, nil
}
