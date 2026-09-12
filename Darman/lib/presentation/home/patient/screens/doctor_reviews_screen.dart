import 'package:darmaan/core/models/consultation_review_model.dart';
import 'package:darmaan/core/models/doctor_review_summary_model.dart';
import 'package:darmaan/core/models/user_model.dart';
import 'package:darmaan/core/theme/app_colors.dart';
import 'package:darmaan/presentation/home/patient/repository/patient_repository.dart';
import 'package:flutter/material.dart';
import 'package:darmaan/core/utils/app_error_message.dart';
import 'package:darmaan/widgets/app_shimmer.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

class DoctorReviewsScreen extends StatefulWidget {
  const DoctorReviewsScreen({super.key, required this.doctor});
  final UserModel doctor;

  @override
  State<DoctorReviewsScreen> createState() => _DoctorReviewsScreenState();
}

class _DoctorReviewsScreenState extends State<DoctorReviewsScreen> {
  static const _pageSize = 20;
  final _repository = PatientRepository();
  final _scrollController = ScrollController();
  final List<ConsultationReviewModel> _reviews = [];
  DoctorReviewSummaryModel? _summary;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 300 &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repository.getDoctorReviewSummary(widget.doctor.uid),
        _repository.getDoctorReviews(widget.doctor.uid, limit: _pageSize),
      ]);
      if (!mounted) return;
      final items = results[1] as List<ConsultationReviewModel>;
      setState(() {
        _summary = results[0] as DoctorReviewSummaryModel;
        _reviews
          ..clear()
          ..addAll(items);
        _hasMore = items.length == _pageSize;
      });
    } catch (error) {
      if (mounted) setState(() => _error = AppErrorMessage.from(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final items = await _repository.getDoctorReviews(
        widget.doctor.uid,
        limit: _pageSize,
        offset: _reviews.length,
      );
      if (!mounted) return;
      setState(() {
        _reviews.addAll(
          items.where((item) => !_reviews.any((old) => old.id == item.id)),
        );
        _hasMore = items.length == _pageSize;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorMessage.from(error)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Patient reviews', style: GoogleFonts.outfit(
          fontSize: 18, fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        )),
      ),
      body: _loading
          ? const AppListShimmer(itemCount: 5, horizontalPadding: 16)
          : _error != null
          ? Center(
              child: FilledButton(
                onPressed: _loadInitial,
                child: const Text('Try again'),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadInitial,
              child: ListView.separated(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: (_reviews.isEmpty ? 2 : _reviews.length + 1) +
                    (_loadingMore ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == 0) return _SummaryCard(summary: _summary!);
                  if (_reviews.isEmpty && index == 1) {
                    return const _NoReviews();
                  }
                  final reviewIndex = index - 1;
                  if (reviewIndex >= _reviews.length) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _ReviewCard(review: _reviews[reviewIndex]);
                },
              ),
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final DoctorReviewSummaryModel summary;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(
        color: Colors.black.withValues(alpha: 0.035),
        blurRadius: 16,
        offset: const Offset(0, 4),
      )],
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                summary.averageRating.toStringAsFixed(1),
                style: GoogleFonts.outfit(fontSize: 34,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary),
              ),
              Row(children: [
                const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFB300)),
                const SizedBox(width: 4),
                Text('${summary.reviewCount} reviews', style: GoogleFonts.outfit(
                  fontSize: 11.5, color: AppColors.textSecondary)),
              ]),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                for (var stars = 5; stars >= 1; stars--)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(width: 18, child: Text('$stars')),
                        const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: LinearProgressIndicator(
                              value: summary.fractionFor(stars),
                              minHeight: 6,
                              backgroundColor: const Color(0xFFF0F1F3),
                              valueColor: const AlwaysStoppedAnimation(Color(0xFFFFB300)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final ConsultationReviewModel review;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.brand.withValues(alpha: 0.09),
                child: Text(
                  review.patientName.trim().isEmpty
                      ? 'P'
                      : review.patientName.trim()[0].toUpperCase(),
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w500,
                    color: AppColors.brand),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(review.patientName, style: GoogleFonts.outfit(
                    fontSize: 14, fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('Verified consultation', style: GoogleFonts.outfit(
                    fontSize: 10.5, color: AppColors.brand)),
                ]),
              ),
              Text(DateFormat('d MMM yyyy').format(review.createdAt.toLocal()),
                style: GoogleFonts.outfit(fontSize: 10.5,
                  color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(
              5,
              (index) => Icon(
                index < review.rating
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                size: 18,
                color: Colors.amber.shade700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (review.review?.trim().isNotEmpty == true)
            Text(review.review!, style: GoogleFonts.outfit(
              fontSize: 13, height: 1.45, color: AppColors.textPrimary))
          else
            Text('Rating only', style: GoogleFonts.outfit(
              fontSize: 12, fontStyle: FontStyle.italic,
              color: AppColors.textSecondary)),
        ],
      ),
    ),
  );
}

class _NoReviews extends StatelessWidget {
  const _NoReviews();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(children: [
      Icon(Icons.rate_review_outlined, size: 48, color: Colors.grey.shade300),
      const SizedBox(height: 14),
      Text('No reviews yet', style: GoogleFonts.outfit(
        fontSize: 15, fontWeight: FontWeight.w500,
        color: AppColors.textPrimary)),
      const SizedBox(height: 5),
      Text('Patient feedback will appear here after consultations.',
        textAlign: TextAlign.center,
        style: GoogleFonts.outfit(fontSize: 11.5,
          color: AppColors.textSecondary)),
    ]),
  );
}
