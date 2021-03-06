/* stats.c */

/* 2012/09/28, Jan Gustafsson <jan.gustafsson@mdh.se>
 * Changes:
 *  - time is only enabled if the POUT flag is set
 *  - st.c:30:1:  main () warning: type specifier missing, defaults to 'int': fixed
 */


/* 2011/10/18, Benedikt Huber <benedikt@vmars.tuwien.ac.at>
 * Changes:
 *  - Measurement and Printing the Results is only enabled if the POUT flag is set
 *  - Added Prototypes for InitSeed and RandomInteger
 *  - Changed return type of InitSeed from 'missing (default int)' to 'void'
 */

#ifdef POUT
#include <sys/types.h>
#include <sys/times.h>
#include <math.h>
#endif

#define MAX 1000

void initSeed(void);
int randomInteger();


/* Statistics Program:
 * This program computes for two arrays of numbers the sum, the
 * mean, the variance, and standard deviation.  It then determines the
 * correlation coefficient between the two arrays.
 */

int Seed;
double ArrayA[MAX], ArrayB[MAX];
double SumA, SumB;
double Coef;

int main ()
{
#ifdef POUT
   long StartTime, StopTime;
   float TotalTime;
#endif

   double MeanA, MeanB, VarA, VarB, StddevA, StddevB /*, Coef*/;
   int ttime();
   void initialize(), calc_Sum_Mean(), calc_Var_Stddev();
   void calc_LinCorrCoef();

   initSeed ();
#ifdef POUT
   printf ("\n   *** Statictics TEST ***\n\n");
   StartTime = ttime();
#endif

   initialize(ArrayA);
   calc_Sum_Mean(ArrayA, &SumA, &MeanA);
   calc_Var_Stddev(ArrayA, MeanA, &VarA, &StddevA);

   initialize(ArrayB);
   calc_Sum_Mean(ArrayB, &SumB, &MeanB);
   calc_Var_Stddev(ArrayB, MeanB, &VarB, &StddevB);

   /* Coef will have to be used globally in calc_LinCorrCoef since it would
      be beyond the 6 registers used for passing parameters
   */
   calc_LinCorrCoef(ArrayA, ArrayB, MeanA, MeanB /*, &Coef*/);

#ifdef POUT
   StopTime = ttime();
   TotalTime = (StopTime - StartTime) / 1000.0;
   printf("     Sum A = %12.4f,      Sum B = %12.4f\n", SumA, SumB);
   printf("    Mean A = %12.4f,     Mean B = %12.4f\n", MeanA, MeanB);
   printf("Variance A = %12.4f, Variance B = %12.4f\n", VarA, VarB);
   printf(" Std Dev A = %12.4f, Variance B = %12.4f\n", StddevA, StddevB);
   printf("\nLinear Correlation Coefficient = %f\n", Coef);
#endif
}


void initSeed ()
/*
 * Initializes the seed used in the random number generator.
 */
{
   Seed = 0;
}


void calc_Sum_Mean(Array, Sum, Mean)
double Array[], *Sum;
double *Mean;
{
   int i;

   *Sum = 0;
   for (i = 0; i < MAX; i++)
      *Sum += Array[i];
   *Mean = *Sum / MAX;
}


double Square(x)
double x;
{
   return x*x;
}


void calc_Var_Stddev(Array, Mean, Var, Stddev)
double Array[], Mean, *Var, *Stddev;
{
   int i;
   double diffs;

   diffs = 0.0;
   for (i = 0; i < MAX; i++)
      diffs += Square(Array[i] - Mean);
   *Var = diffs/MAX;
   *Stddev = sqrt(*Var);
}


void calc_LinCorrCoef(ArrayA, ArrayB, MeanA, MeanB /*, Coef*/)
double ArrayA[], ArrayB[], MeanA, MeanB /*, *Coef*/;
{
   int i;
   double numerator, Aterm, Bterm;

   numerator = 0.0;
   Aterm = Bterm = 0.0;
   for (i = 0; i < MAX; i++) {
      numerator += (ArrayA[i] - MeanA) * (ArrayB[i] - MeanB);
      Aterm += Square(ArrayA[i] - MeanA);
      Bterm += Square(ArrayB[i] - MeanB);
      }

   /* Coef used globally */
   Coef = numerator / (sqrt(Aterm) * sqrt(Bterm));
}
    


void initialize(Array)
double Array[];
/*
 * Intializes the given array with random integers.
 */
{
  register int i;

for (i=0; i < MAX; i++)
   Array [i] = i + randomInteger ()/8095.0;
}


int randomInteger()
/*
 * Generates random integers between 0 and 8095
 */
{
   Seed = ((Seed * 133) + 81) % 8095;
   return (Seed);
}

#ifdef POUT
int ttime()
/*
 * This function returns in milliseconds the amount of compiler time
 *  used prior to it being called.
 */
{
   struct tms buffer;
   int utime;

   times(&buffer);
   utime = (buffer.tms_utime / 60.0) * 1000.0;
   return (utime);
}
#endif
